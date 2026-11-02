# frozen_string_literal: true

module Reanimator
  module Detectors
    # Detects the Ruby/Bundler ecosystem and the supported-runtime matrix
    # (specification section 06: Ecosystem and Support matrix). Evidence is the
    # presence of a Gemfile, a lockfile, and any runtime pin - .ruby-version,
    # a gemspec `required_ruby_version`, or a Gemfile `ruby` directive.
    class Bundler < Base
      GEMFILE_RUBY = /^\s*ruby\s+['"]([^'"]+)['"]/

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

      # Each root gemspec's floor, read by parsing (ADR-011).
      # Every gemspec counts - a project can ship more than one, and the
      # lowest floor wins downstream.
      def gemspec_floors
        @gemspec_floors ||= repository.glob("*.gemspec").sort
          .select { |path| File.file?(repository.absolute(path)) }
          .map { |path| GemspecFloor.new(path, *floor_reader.read(path)) }
      end

      def floor_reader = @floor_reader ||= FloorReader.new(repository)

      # The first gemspec floor Reanimator could not read, or nil.
      def unreadable_floor
        floor = gemspec_floors.find(&:unreadable)
        floor && Pin.new(floor.unreadable, floor.path)
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
