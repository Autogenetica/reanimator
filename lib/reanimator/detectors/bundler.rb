# frozen_string_literal: true

module Reanimator
  module Detectors
    # Detects the Ruby/Bundler ecosystem and the supported-runtime matrix
    # (specification section 06: Ecosystem and Support matrix). Evidence is the
    # presence of a Gemfile, a lockfile, and any runtime pin - .ruby-version,
    # a gemspec `required_ruby_version`, or a Gemfile `ruby` directive.
    class Bundler < Base
      RUBY_VERSION_PIN = /required_ruby_version\s*=?\s*['"]?([^'"]+)['"]?/
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

      # Every quoted requirement on any line that sets or mentions
      # required_ruby_version, so [">= 3.1", "< 4"] and
      # Gem::Requirement.new(">= 3.1") are read as the requirements they are.
      # A mention that is not the real assignment - in a =begin block, a
      # comment after other code, a description - can only add a floor, and
      # the lowest floor wins, so a stray mention can only under-credit. An
      # unquoted value is taken as written.
      def gemspec_requirements(body, match)
        quoted = requirement_texts(body).flat_map { |text| text.scan(/["']([^"']+)["']/).flatten }
        quoted.empty? ? [match[1].strip] : quoted.map(&:strip).uniq
      end

      # The text from each mention of required_ruby_version, through the
      # closing bracket when an array spans several lines, without the
      # comment that may trail it. Lines that are wholly comments are skipped.
      def requirement_texts(body)
        lines = body.lines
        lines.each_index.filter_map do |index|
          line = lines[index]
          next if line.lstrip.start_with?("#") || !line.include?("required_ruby_version")

          text = line[/required_ruby_version.*/m] + array_continuation(line, lines.drop(index + 1))
          text.lines.map { |l| l.sub(/\s+#.*$/, "") }.join
        end
      end

      # The lines that close an array opened, but not closed, on this line.
      def array_continuation(line, rest)
        return "" unless line.include?("[") && !line.include?("]")

        rest[0..(rest.index { |l| l.include?("]") } || -1)].join
      end

      # @return [Array<Pin>] de-duplicated runtime pins, strongest source first
      def runtime_pins
        pins = []

        if (rv = repository.read(".ruby-version"))
          pins << Pin.new(rv.strip, ".ruby-version")
        end
        if (gemspec = first_path("*.gemspec")) && (body = repository.read(gemspec)) &&
            (m = body.match(RUBY_VERSION_PIN))
          gemspec_requirements(body, m).each { |requirement| pins << Pin.new(requirement, gemspec) }
        end
        if (gemfile = repository.read("Gemfile")) && (m = gemfile.match(GEMFILE_RUBY))
          pins << Pin.new(m[1].strip, "Gemfile")
        end

        pins.uniq(&:version)
      end
    end
  end
end
