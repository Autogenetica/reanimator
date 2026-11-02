# frozen_string_literal: true

module Reanimator
  module Detectors
    # Detects the Ruby/Bundler ecosystem and the supported-runtime matrix
    # (specification section 06: Ecosystem and Support matrix). Evidence is the
    # presence of a Gemfile, a lockfile, and any runtime pin - .ruby-version,
    # a gemspec `required_ruby_version`, or a Gemfile `ruby` directive.
    class Bundler < Base
      # The assignment that declares a gem's Ruby floor, e.g.
      # `spec.required_ruby_version = ">= 3.1"`.
      FLOOR_ASSIGNMENT = /(?:\A|[\s;{|(])\w+\.required_ruby_version\s*=(?!=)/
      QUOTED = /"([^"]*)"|'([^']*)'/
      # What may surround the string literals of a readable floor: brackets,
      # commas, Gem::Requirement.new(...) and .freeze. Anything else - a
      # constant, an interpolation, a heredoc, File.read - is not a literal.
      LITERAL_SCAFFOLD = /\A[\s\[\](),]*[\s;}]*\z/
      GEMFILE_RUBY = /^\s*ruby\s+['"]([^'"]+)['"]/

      # How a gemspec loads another file, e.g. `require_relative "lib/w/version"`.
      LOAD = /(?:\A|;)\s*(require_relative|require|load)\b[\s(]+(.*)/
      # A load path written as a literal, or built from one beside the loading
      # file: File.expand_path("x", __dir__) or File.expand_path("../x", __FILE__).
      LITERAL_PATH = /\A["']([^"'#]*)["']/
      EXPANDED_PATH = /\AFile\.expand_path\(\s*["']([^"'#]*)["']\s*,\s*(__dir__|__FILE__|File\.dirname\(__FILE__\))\s*\)/
      # Or joined to the loading file's directory: File.dirname(__FILE__) + "/x".
      JOINED_PATH = /\A(?:File\.dirname\(__FILE__\)|__dir__)\s*\+\s*["']\/?([^"'#]*)["']/
      # How many levels of loads Reanimator follows from a gemspec.
      MAX_LOAD_DEPTH = 4

      # A line that carries on the expression above it: a method chain or a
      # boolean operator at the start of the next line changes the value.
      CONTINUATION = /\A\s*(?:\.|&\.|&&|\|\||and\b|or\b)/

      # A single declared runtime version paired with the file it came from.
      Pin = Struct.new(:version, :source)
      # What one gemspec declares: its literal requirements, or why they could
      # not be read.
      GemspecFloor = Struct.new(:path, :requirements, :unreadable)

      def detect
        return [] unless repository.exist?("Gemfile") || repository.any?("*.gemspec")

        facts = [
          fact(:bundler, category: :ecosystem,
            claim: "Managed with Bundler.",
            confidence: :high, source: gemfile_or_gemspec, method: :file_present)
        ]

        if repository.exist?("Gemfile.lock")
          facts << fact(:locked_dependencies, category: :ecosystem,
            claim: "Dependencies are locked (Gemfile.lock present).",
            confidence: :high, source: "Gemfile.lock", method: :file_present)
        end

        unread = unreadable_floor
        if unread
          facts << fact(:supported_ruby_unreadable, category: :support_matrix,
            claim: "#{unread.source} sets its Ruby floor in a way Reanimator cannot read: #{unread.version}.",
            value: unread.version, confidence: :high, source: unread.source, method: :version_pin, detail: unread.version)
        end

        pins = runtime_pins
        unless pins.empty?
          versions = pins.map(&:version)
          facts << fact(:supported_ruby, category: :support_matrix,
            claim: "Declared Ruby support: #{versions.join(", ")}.",
            value: versions, confidence: :medium,
            source: pins.first.source, method: :version_pin, detail: versions.join(", "))
        end

        facts
      end

      private

      def gemfile_or_gemspec
        repository.exist?("Gemfile") ? "Gemfile" : first_path("*.gemspec")
      end

      # Each root gemspec's floor.
      # Every gemspec counts - a project can ship more than one, and the
      # lowest floor wins downstream.
      def gemspec_floors
        @gemspec_floors ||= repository.glob("*.gemspec").sort
          .select { |path| File.file?(repository.absolute(path)) }
          .map { |path| GemspecFloor.new(path, *read_gemspec(path)) }
      end

      # The requirements a gemspec and the local files it loads declare, each
      # file read on its own, or [[], reason] for the first thing Reanimator
      # could not read or follow. A load it cannot follow may lower the floor,
      # so it makes the floor unreadable - unless the gemspec itself assigns a
      # literal floor, the owner's own statement, which then settles it.
      def read_gemspec(gemspec)
        requirements, own = [], nil
        unfollowed = each_source(gemspec) do |file, body|
          return [[], "#{relative(file)} could not be read"] unless body

          found, unreadable = read_floor(body)
          return [[], file_reason(unreadable, file, gemspec)] if unreadable

          own ||= found # the gemspec is yielded first
          requirements.concat(found)
        end
        (own.empty? && unfollowed) ? [[], unfollowed] : [requirements.uniq, nil]
      end

      # Yields the gemspec and each repository file it loads, breadth first,
      # with its text (nil when unreadable). Returns why a load could not be
      # followed, or nil.
      def each_source(gemspec)
        unfollowed, seen = nil, Set.new
        pending = [[real_path(repository.absolute(gemspec)), 0]]
        until pending.empty?
          file, depth = pending.shift
          next unless seen.add?(file)

          body = read_source(file)
          yield file, body
          next unless body

          loads, unfollowable = loaded_files(body, file)
          unfollowed ||= unfollowable && "it loads `#{unfollowable}`, which Reanimator cannot follow"
          next if loads.empty?

          if depth < MAX_LOAD_DEPTH
            pending.concat(loads.map { |path| [path, depth + 1] })
          else
            unfollowed ||= "it loads files more than #{MAX_LOAD_DEPTH} levels deep"
          end
        end
        unfollowed
      end

      # The repository files this body loads, and the first load Reanimator
      # could not follow, or nil.
      def loaded_files(body, file)
        unfollowed = nil
        paths = body.lines.filter_map do |line|
          next if comment?(line) || !(load = LOAD.match(line))

          target = load_target(*load.captures, file)
          unfollowed ||= line.strip unless target
          target unless target == :library
        end
        [paths, unfollowed]
      end

      # Where a load leads: a repository file, :library for a require Ruby
      # finds among installed gems, or nil when Reanimator cannot follow it -
      # a path built at runtime, or one outside the repository.
      def load_target(kind, argument, file)
        literal = argument[LITERAL_PATH, 1]
        return repository_file(File.join(root, "lib", ruby_file(literal))) || :library if library?(kind, literal)

        path = load_path(kind, argument, file)
        path && repository_file((kind == "load") ? path : ruby_file(path))
      rescue ArgumentError, EncodingError
        nil
      end

      # A bare require of a literal name: Ruby searches the load path for it.
      def library?(kind, literal)
        kind == "require" && literal && !literal.start_with?("./", "../", "/")
      end

      # The absolute path a load names, or nil when it is built at runtime.
      # Paths are resolved as Ruby does, with File.absolute_path: a leading ~
      # names no home directory, and a path Ruby could not use is unfollowed.
      def load_path(kind, argument, file)
        if (expanded = EXPANDED_PATH.match(argument))
          File.absolute_path(expanded[1], (expanded[2] == "__FILE__") ? file : File.dirname(file))
        elsif (joined = argument[JOINED_PATH, 1])
          File.absolute_path(joined, File.dirname(file))
        elsif (literal = argument[LITERAL_PATH, 1])
          File.absolute_path(literal, (kind == "require_relative") ? File.dirname(file) : root)
        end
      end

      def ruby_file(path) = path.end_with?(".rb") ? path : "#{path}.rb"

      # The real path of a regular file inside the repository, or nil - a
      # symlink out of the repository is outside it.
      def repository_file(path)
        real = File.realpath(path)
        real if real.start_with?("#{root}/") && File.file?(real)
      rescue SystemCallError
        nil
      end

      def root = @root ||= real_path(repository.path)

      def real_path(path)
        File.realpath(path)
      rescue SystemCallError
        path
      end

      def relative(file) = file.delete_prefix("#{root}/")

      # A file's text as UTF-8, whatever the locale, or nil when it cannot be
      # read.
      def read_source(file)
        File.read(file, encoding: "UTF-8").scrub
      rescue SystemCallError, IOError
        nil
      end

      def file_reason(reason, file, gemspec)
        (relative(file) == gemspec) ? reason : "#{reason} in #{relative(file)}"
      end

      # The requirements a body declares, and why Reanimator could not read
      # them. Every live line that mentions required_ruby_version must be a
      # complete assignment of string literals - [">= 3.1", "< 4"] and
      # Gem::Requirement.new(">= 3.1") included - or the whole floor is
      # unreadable: a mention that is not understood never silently becomes
      # "no floor", which would credit any matrix. A mention after __END__ or
      # inside =begin is unreadable too: a heredoc can make either one text,
      # and a line-by-line reader cannot tell.
      def read_floor(body)
        classified = classified_lines(body)
        hidden = classified.find { |line, kind| kind == :hidden && line.include?("required_ruby_version") }
        return [[], "`#{hidden[0].strip}` sits after __END__ or inside =begin, where it may be code"] if hidden

        lines = classified.map { |line, kind| (kind == :code) ? line : "\n" }
        requirements = lines.each_index.flat_map do |index|
          next [] unless lines[index].include?("required_ruby_version")

          value = assigned_value(lines[index], lines.drop(index + 1))
          return [[], "`#{lines[index].strip}` is not a literal"] unless value && literal?(value) && !continued?(lines, index, value)

          literals(value)
        end
        [requirements.uniq, nil]
      end

      # Whether the value carries on past the assignment (and any array it
      # spans), so the literal is not what Ruby assigns: a trailing comma
      # makes an array of the next line, and a chain or operator on the next
      # line changes the value.
      def continued?(lines, index, value)
        return true if value.rstrip.end_with?(",")

        following = lines.drop(index + value.lines.size).find { |line| !line.strip.empty? }
        following && CONTINUATION.match?(following)
      end

      # The literal requirements every gemspec declares.
      def gemspec_requirements = gemspec_floors.flat_map(&:requirements).uniq

      # The string literals in an assigned value, in order.
      def literals(value) = value.scan(QUOTED).map { |pair| pair.compact.first.strip }

      # The first gemspec floor Reanimator could not read, or nil.
      def unreadable_floor
        floor = gemspec_floors.find(&:unreadable)
        floor && Pin.new(floor.unreadable, floor.path)
      end

      # At least one string literal, and nothing around the literals but
      # brackets, commas, Gem::Requirement.new(...) and .freeze.
      def literal?(value)
        return false if value.include?("\#{") || literals(value).empty?

        LITERAL_SCAFFOLD.match?(value.gsub(QUOTED, "").gsub("Gem::Requirement.new", "").gsub(".freeze", ""))
      end

      # The right-hand side of a floor assignment on this line, through the
      # closing bracket when an array spans lines and without a trailing
      # comment - or nil when the line is not such an assignment.
      def assigned_value(line, rest)
        before, value = line.split(FLOOR_ASSIGNMENT, 2)
        return unless value && before

        (value + array_continuation(value, rest)).lines.map { |l| without_comment(l) }.join
      end

      # The line up to a # that starts a comment - one outside any string.
      def without_comment(line)
        quote = nil
        line.each_char.with_index do |char, index|
          if quote
            quote = nil if char == quote
          elsif char == '"' || char == "'"
            quote = char
          elsif char == "#"
            return "#{line[0...index].rstrip}\n"
          end
        end
        line
      end

      # Each line with what Ruby makes of it: :code, :comment for a full-line
      # comment, or :hidden inside =begin/=end and from __END__ on. A =begin
      # never closed hides the rest of the file, so any floor after it is
      # unreadable rather than ignored.
      def classified_lines(body)
        in_block = ended = false
        body.lines.map do |line|
          ended ||= !in_block && line.chomp == "__END__"
          in_block = true if !ended && line.start_with?("=begin")
          kind = if ended || in_block
            :hidden
          elsif comment?(line)
            :comment
          else
            :code
          end
          in_block = false if line.start_with?("=end")
          [line, kind]
        end
      end

      # A full-line comment. A line starting with #{ is interpolation inside
      # a string, not a comment.
      def comment?(line) = line.lstrip.start_with?("#") && !line.lstrip.start_with?("\#{")

      # The lines that close an array opened, but not closed, in this value.
      def array_continuation(value, rest)
        return "" unless value.include?("[") && !value.include?("]")

        rest[0..(rest.index { |l| l.include?("]") } || -1)].join
      end

      # @return [Array<Pin>] de-duplicated runtime pins, strongest source first
      def runtime_pins
        pins = []

        if (rv = repository.read(".ruby-version"))
          pins << Pin.new(rv.strip, ".ruby-version")
        end
        gemspec_floors.each do |floor|
          floor.requirements.each { |requirement| pins << Pin.new(requirement, floor.path) }
        end
        if (gemfile = repository.read("Gemfile")) && (m = gemfile.match(GEMFILE_RUBY))
          pins << Pin.new(m[1].strip, "Gemfile")
        end

        pins.uniq(&:version)
      end
    end
  end
end
