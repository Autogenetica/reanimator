# frozen_string_literal: true

require "prism"

module Reanimator
  # Reads the Ruby floor a gemspec declares - its `required_ruby_version` -
  # by parsing the gemspec and the local files it loads, never by running
  # them (ADR-011). Parsing sees what Ruby sees: statements after `;`,
  # modifiers, heredocs, `=begin` and `__END__` all mean what they mean to
  # Ruby, so the reader cannot be misled by how a line looks.
  #
  # Every floor assignment anywhere counts, and the lowest wins downstream, so
  # reading an assignment Ruby would skip - in a branch, or a helper never
  # called - can only make the check stricter. What must never happen is
  # missing one: so any other way of reaching the floor (`send`, `||=`, a
  # value that is not a literal, `eval`, a load Reanimator cannot follow)
  # makes the floor unreadable instead.
  class FloorReader
    FLOOR = :required_ruby_version
    FLOOR_WRITE = :required_ruby_version=
    FLOOR_IVAR = :@required_ruby_version
    LOADS = %i[require require_relative load].freeze
    # Calls that run code given as a string, which a parse cannot see into.
    EVALS = %i[eval instance_eval class_eval module_eval].freeze
    # Names that reach a load or an eval when called indirectly - by send,
    # method(...).call - so the parse cannot see what they load or run.
    INDIRECT = (LOADS + EVALS + %i[autoload]).map(&:to_s).freeze
    # The load path, which decides where a bare require leads, and the calls
    # that add to it.
    LOAD_PATH = %i[$LOAD_PATH $: $-I].freeze
    LOAD_PATH_ADDS = %i[unshift << push prepend insert concat append].freeze
    # How many levels of loads are followed from a gemspec.
    MAX_LOAD_DEPTH = 4
    # Bounds on what is parsed at all. Real gemspecs are a few kilobytes and a
    # few levels deep; far past that, Prism and the reader can exhaust the
    # stack, and an overflow repeated in one process can kill it outright.
    MAX_BYTES = 256 * 1024
    MAX_NESTING = 1_000

    # What one file says about the floor: the requirements it assigns, the
    # first thing it could not read, the repository files it loads, the first
    # load it could not follow, whether the file could be read at all, and
    # whether it changes the load path.
    Reading = Struct.new(:requirements, :unreadable, :loads, :unfollowed, :unread, :load_path)

    # @param repository [Repository]
    def initialize(repository)
      @repository = repository
    end

    # The requirements a gemspec and the local files it loads declare, or
    # [[], reason] for the first thing Reanimator could not read or follow. A
    # load it cannot follow may lower the floor, so it makes the floor
    # unreadable - unless the gemspec itself assigns a literal floor, the
    # owner's own statement, which then settles it.
    # @return [Array(Array<String>, String, nil)]
    def read(gemspec)
      requirements, own = [], nil
      unfollowed = each_reading(gemspec) do |file, reading|
        return [[], "#{relative(file)} could not be read"] if reading.unread
        return [[], file_reason(reading.unreadable, file, gemspec)] if reading.unreadable

        own ||= reading.requirements # the gemspec is read first
        requirements.concat(reading.requirements)
      end
      (own.empty? && unfollowed) ? [[], unfollowed] : [requirements.uniq, nil]
    end

    private

    attr_reader :repository

    # Yields the gemspec and each repository file it loads, breadth first,
    # with what each says. Returns why a load could not be followed, or nil.
    def each_reading(gemspec)
      unfollowed, seen = nil, Set.new
      start = real_path(repository.absolute(gemspec))
      linked = start != File.join(root, gemspec)
      pending = [[start, 0]]
      until pending.empty?
        file, depth = pending.shift
        next unless seen.add?(file)

        reading = read_file(file)
        yield file, reading
        unfollowed ||= reading.unfollowed && "it loads `#{reading.unfollowed}`, which Reanimator cannot follow"
        next if reading.loads.empty?

        # A symlinked gemspec's loads resolve from where the link sits.
        if linked && file == start
          unfollowed ||= "it is a symlink, so the files it loads cannot be placed"
        elsif depth < MAX_LOAD_DEPTH
          pending.concat(reading.loads.map { |path| [path, depth + 1] })
        else
          unfollowed ||= "it loads files more than #{MAX_LOAD_DEPTH} levels deep"
        end
      end
      unfollowed
    end

    def read_file(file)
      reading = Reading.new([], nil, [], nil, false, false)
      body = read_source(file)
      unless body
        reading.unread = true
        return reading
      end
      return refused(reading, "it is too large to read") if body.bytesize > MAX_BYTES
      return refused(reading, "it is nested too deeply to read") if nesting(body) > MAX_NESTING

      parsed = Prism.parse(body)
      return refused(reading, "it does not parse as Ruby") if parsed.failure?

      nodes = flatten(parsed.value)
      reading.load_path = load_path_changed?(nodes, file)
      nodes.each { |node| visit(node, file, body.lines, reading) }
      reading
    rescue SystemStackError
      refused(reading, "it is nested too deeply to read")
    end

    # A reading that stops at its first refusal, with nothing else read.
    def refused(reading, reason)
      reading.unreadable = reason
      reading
    end

    # The deepest run of open brackets, counted without regard to strings - an
    # overestimate, which only ever refuses more.
    def nesting(body)
      depth = deepest = 0
      body.each_char do |char|
        if "([{".include?(char)
          depth += 1
          deepest = depth if depth > deepest
        elsif ")]}".include?(char)
          depth -= 1
        end
      end
      deepest
    end

    # Every node in the tree, in source order, walked without recursion so
    # that deep nesting cannot exhaust the stack.
    def flatten(tree)
      nodes, pending = [], [tree]
      while (node = pending.pop)
        nodes << node
        pending.concat(node.compact_child_nodes.reverse)
      end
      nodes
    end

    # Whether the file puts anything but the repository's lib/ on the load
    # path - which a gem does as a matter of course, and the reader assumes.
    # Then a bare require may lead elsewhere, so the reader does not guess.
    def load_path_changed?(nodes, file)
      lib = File.join(root, "lib")
      assigned = nodes.grep(Prism::LocalVariableWriteNode).to_h { |node| [node.name, node.value] }
      nodes.any? do |node|
        case node
        when Prism::GlobalVariableWriteNode, Prism::GlobalVariableOperatorWriteNode
          LOAD_PATH.include?(node.name)
        when Prism::CallNode
          node.receiver.is_a?(Prism::GlobalVariableReadNode) && LOAD_PATH.include?(node.receiver.name) &&
            LOAD_PATH_ADDS.include?(node.name) &&
            !(node.arguments&.arguments || []).all? { |added| adds_lib?(added, assigned, file, lib) }
        end
      end
    end

    def adds_lib?(node, assigned, file, lib)
      node = assigned[node.name] if node.is_a?(Prism::LocalVariableReadNode)
      path = node.is_a?(Prism::StringNode) ? File.expand_path(node.unescaped, root) : built_path(node, file)
      path == lib
    rescue ArgumentError
      false
    end

    def visit(node, file, lines, reading)
      case node
      when Prism::CallNode then call(node, file, lines, reading)
      when Prism::CallOrWriteNode, Prism::CallAndWriteNode, Prism::CallOperatorWriteNode
        unreadable(reading, node, lines) if node.read_name == FLOOR
      when Prism::CallTargetNode
        unreadable(reading, node, lines) if node.name == FLOOR_WRITE
      when Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode,
        Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableOperatorWriteNode,
        Prism::InstanceVariableTargetNode
        unreadable(reading, node, lines) if node.name == FLOOR_IVAR
      when Prism::DefNode
        # A method named for the floor replaces what the setter does.
        unreadable(reading, node, lines) if [FLOOR, FLOOR_WRITE].include?(node.name)
      when Prism::SymbolNode, Prism::StringNode
        name(node.unescaped, node, lines, reading)
      end
    end

    # A symbol or string that names the floor reaches it indirectly - send,
    # instance_variable_set - and one that names a load or an eval runs code
    # the parse cannot see. Prose that merely mentions them is just text.
    def name(text, node, lines, reading)
      if text.match?(/\A@?#{FLOOR}=?\z/o)
        unreadable(reading, node, lines)
      elsif INDIRECT.include?(text)
        reading.unfollowed ||= line_of(node, lines)
      end
    end

    def call(node, file, lines, reading)
      if node.name == FLOOR_WRITE
        found = literals(node.arguments&.arguments&.first)
        found ? reading.requirements.concat(found) : unreadable(reading, node, lines)
      elsif LOADS.include?(node.name) && kernel?(node.receiver)
        follow(load_target(node.name, node.arguments&.arguments&.first, file, reading), node, lines, reading)
      elsif node.name == :autoload && node.arguments&.arguments&.size == 2
        follow(load_target(:require, node.arguments.arguments.last, file, reading), node, lines, reading)
      elsif node.name == :eval || (EVALS.include?(node.name) && node.arguments)
        # Code run from a string could set any floor, so no literal settles it.
        unreadable(reading, node, lines)
      elsif node.name == :load && node.receiver&.slice&.end_with?("Specification")
        reading.unfollowed ||= line_of(node, lines)
      end
    end

    def follow(target, node, lines, reading)
      reading.loads << target if target.is_a?(String)
      reading.unfollowed ||= line_of(node, lines) unless target
    end

    # The string literals assigned as the floor, or nil when the value is
    # anything else: ">= 3.1", [">= 3.1", "< 4"], ">= 3.1".freeze and
    # Gem::Requirement.new(">= 3.1") are literals; a constant, an
    # interpolation or a method call on them is not.
    def literals(node)
      case node
      when Prism::StringNode then [node.unescaped.strip]
      when Prism::ArrayNode then all_literals(node.elements)
      when Prism::CallNode
        if node.name == :freeze && node.receiver && !node.arguments
          literals(node.receiver)
        elsif node.name == :new && node.receiver&.slice&.delete_prefix("::") == "Gem::Requirement"
          all_literals(node.arguments&.arguments || [])
        end
      end
    end

    # The literals of every node, or nil when any one is not literal.
    def all_literals(nodes)
      found = nodes.map { |node| literals(node) }
      found.flatten if found.all?
    end

    def kernel?(receiver) = receiver.nil? || receiver.slice.delete_prefix("::") == "Kernel"

    # Where a load leads: a repository file, :library for a require Ruby
    # finds among installed gems, or nil when Reanimator cannot follow it -
    # a path built at runtime, one outside the repository or through a
    # symlink, or one Ruby could not use.
    def load_target(kind, argument, file, reading)
      if argument.is_a?(Prism::StringNode)
        literal_target(kind, argument.unescaped, file, reading.load_path)
      elsif (path = built_path(argument, file))
        repository_file((kind == :load) ? path : ruby_file(path))
      end
    rescue ArgumentError, EncodingError
      nil
    end

    # Paths are resolved as Ruby resolves them: require_relative keeps a
    # leading ~ as written, while load and require expand it - to a home
    # directory outside the repository, or to an error - and so leave the
    # load unfollowed. A bare name is searched for in lib/, which a gem puts
    # on its load path; one that is there in any form Reanimator cannot place
    # exactly - a symlink, a different case - is not a library.
    def literal_target(kind, literal, file, load_path)
      bare = !literal.start_with?("./", "../", "/", "~")
      # A file that changes the load path decides itself where a bare name
      # leads, so Reanimator does not guess.
      return if bare && load_path && kind != :require_relative

      case kind
      when :require_relative
        repository_file(ruby_file(File.absolute_path(literal, File.dirname(file))))
      when :require
        return repository_file(File.expand_path(ruby_file(literal), root)) unless bare

        in_lib = File.join(root, "lib", ruby_file(literal))
        repository_file(in_lib) || (File.exist?(in_lib) ? nil : :library)
      when :load
        in_lib = File.join(root, "lib", literal)
        repository_file((bare && File.exist?(in_lib)) ? in_lib : File.expand_path(literal, root))
      end
    end

    # The path File.expand_path("x", __dir__), File.expand_path("../x",
    # __FILE__), File.dirname(__FILE__) + "/x" or __dir__ + "/x" names, or nil
    # for any other expression.
    def built_path(node, file)
      return unless node.is_a?(Prism::CallNode)

      arguments = node.arguments&.arguments || []
      if node.name == :expand_path && node.receiver&.slice == "File" && arguments.size == 2 &&
          arguments.first.is_a?(Prism::StringNode)
        base = if arguments.last.is_a?(Prism::SourceFileNode)
          file
        elsif here?(arguments.last)
          File.dirname(file)
        end
        File.expand_path(arguments.first.unescaped, base) if base
      elsif node.name == :+ && here?(node.receiver) && arguments.size == 1 &&
          arguments.first.is_a?(Prism::StringNode) && arguments.first.unescaped.start_with?("/")
        File.absolute_path(arguments.first.unescaped.delete_prefix("/"), File.dirname(file))
      end
    end

    # __dir__ or File.dirname(__FILE__): the loading file's directory.
    def here?(node)
      return false unless node.is_a?(Prism::CallNode)

      (node.name == :__dir__ && node.receiver.nil? && node.arguments.nil?) ||
        (node.name == :dirname && node.receiver&.slice == "File" &&
          node.arguments&.arguments&.then { |args| args.size == 1 && args.first.is_a?(Prism::SourceFileNode) })
    end

    def ruby_file(path) = path.end_with?(".rb") ? path : "#{path}.rb"

    # The real path of a regular file inside the repository, or nil. A load
    # through a symlink is not followed: Ruby places a linked file's loads by
    # rules that differ between the gemspec and the files it loads, and
    # Reanimator does not guess which.
    def repository_file(path)
      real = File.realpath(path)
      real if real == path && real.start_with?("#{root}/") && File.file?(real)
    rescue SystemCallError
      nil
    end

    def unreadable(reading, node, lines)
      reading.unreadable ||= "`#{line_of(node, lines)}` is not a literal"
    end

    def line_of(node, lines) = lines[node.location.start_line - 1].to_s.strip

    def file_reason(reason, file, gemspec)
      (relative(file) == gemspec) ? reason : "#{reason} in #{relative(file)}"
    end

    # A file's text as UTF-8, whatever the locale, or nil when it cannot be
    # read.
    def read_source(file)
      File.read(file, encoding: "UTF-8").scrub
    rescue SystemCallError, IOError
      nil
    end

    def root = @root ||= real_path(repository.path)

    def real_path(path)
      File.realpath(path)
    rescue SystemCallError
      path
    end

    def relative(file) = file.delete_prefix("#{root}/")
  end
end
