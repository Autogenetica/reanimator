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

      # A single declared runtime version paired with the file it came from.
      Pin = Struct.new(:version, :source)

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
            claim: "#{unread.source} declares its Ruby floor as `#{unread.version}`, which is not a literal Reanimator can read.",
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

      # Each root gemspec's floor, as [path, requirements, unreadable line].
      # Every gemspec counts - a project can ship more than one, and the
      # lowest floor wins downstream.
      def gemspec_floors
        @gemspec_floors ||= repository.glob("*.gemspec").sort
          .select { |path| File.file?(repository.absolute(path)) }
          .map { |path| [path, *read_floor(repository.read(path).to_s)] }
      end

      # The requirements a gemspec declares, and the first line Reanimator
      # could not read as one. Every live line that mentions
      # required_ruby_version must be a complete assignment of string literals
      # - [">= 3.1", "< 4"] and Gem::Requirement.new(">= 3.1") included -
      # or the whole floor is unreadable: a mention that is not understood
      # never silently becomes "no floor", which would credit any matrix.
      def read_floor(body)
        lines = live_lines(body)
        requirements = lines.each_index.flat_map do |index|
          next [] unless lines[index].include?("required_ruby_version")

          value = assigned_value(lines[index], lines.drop(index + 1))
          return [[], lines[index].strip] unless value && literal?(value)

          literals(value)
        end
        [requirements.uniq, nil]
      end

      # The literal requirements every gemspec declares.
      def gemspec_requirements = gemspec_floors.flat_map { |_path, requirements, _unread| requirements }.uniq

      # The string literals in an assigned value, in order.
      def literals(value) = value.scan(QUOTED).map { |pair| pair.compact.first.strip }

      # The first gemspec floor Reanimator could not read, or nil.
      def unreadable_floor
        path, _requirements, unread = gemspec_floors.find { |_path, _requirements, line| line }
        path && Pin.new(unread, path)
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

      # Code lines only: full-line comments and =begin/=end blocks blanked.
      def live_lines(body)
        in_block = false
        body.lines.map do |line|
          in_block = true if line.start_with?("=begin")
          live = !in_block && !line.lstrip.start_with?("#")
          in_block = false if line.start_with?("=end")
          live ? line : "\n"
        end
      end

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
        gemspec_floors.each do |path, requirements, _unread|
          requirements.each { |requirement| pins << Pin.new(requirement, path) }
        end
        if (gemfile = repository.read("Gemfile")) && (m = gemfile.match(GEMFILE_RUBY))
          pins << Pin.new(m[1].strip, "Gemfile")
        end

        pins.uniq(&:version)
      end
    end
  end
end
