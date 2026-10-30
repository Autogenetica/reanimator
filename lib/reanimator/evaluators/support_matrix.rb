# frozen_string_literal: true

module Reanimator
  module Evaluators
    # A native evaluator that compares declared runtime support against what CI
    # actually exercises. This is the classic escalation from section 16: "the
    # project declares Ruby 3.2 support, but CI no longer tests it." Declared
    # support with no CI coverage is missing evidence, not a pass - and so is a
    # CI matrix whose lowest released Ruby has moved above the declared floor,
    # or one that exercises no released Ruby at all, because support then
    # narrowed while the declaration still promises more.
    class SupportMatrix < Base
      # Requirement operators that state a lower bound on supported versions.
      FLOOR_OPERATORS = %w[>= > ~> =].freeze
      # ">= 0" and friends promise nothing, so they set no floor.
      NO_FLOOR = Gem::Version.new("1")

      def call
        ci = discovery.all(:ci_ruby_matrix).flat_map { |fact| Array(fact.value) }.uniq
        declared = discovery[:supported_ruby]

        graded =
          if ci.any?
            grade_coverage(ci, declared && Array(declared.value))
          elsif declared
            result(:missing_evidence,
              detail: "Ruby #{Array(declared.value).join(", ")} is declared but not exercised in CI.")
          else
            result(:skipped, detail: "No declared runtime support matrix to verify.")
          end
        noting_unread_workflows(graded)
      end

      private

      # A workflow Reanimator could not read is named in any verdict short of
      # verified (where it cannot matter), but it does not soften the verdict: the readable workflows decide, so a
      # narrowing they prove still blocks, and an unread workflow can only mean
      # Reanimator under-credits - the safe direction. Invalid YAML does not run
      # in Actions either; one using YAML aliases does, and its Rubies are
      # simply not counted.
      def noting_unread_workflows(graded)
        unread = discovery.all(:ci_workflow_unreadable)
        return graded if unread.empty? || graded.verified?

        result(graded.status, detail: "#{graded.detail} Not counted: #{unread.map(&:claim).join(" ")}")
      end

      def grade_coverage(ci_versions, declared)
        floor = declared && declared_floor(declared)
        lowest = lowest_release(ci_versions)
        if floor && lowest.nil?
          return result(:missing_evidence,
            detail: "Ruby #{floor} is declared supported, but CI pins no specific released Ruby (#{ci_versions.join(", ")}).")
        end
        if floor && minor(lowest) > minor(floor)
          return result(:missing_evidence,
            detail: "Ruby #{floor} is declared supported, but CI's lowest Ruby is #{lowest}; " \
                    "support narrowed without the declaration changing.")
        end

        result(:verified, detail: "CI exercises Ruby #{ci_versions.join(", ")}.")
      end

      # The lowest version any declared requirement admits, or nil when none
      # states a meaningful lower bound.
      def declared_floor(requirements)
        floors = requirements.flat_map do |requirement|
          Gem::Requirement.new(requirement).requirements
            .filter_map { |operator, version| version if FLOOR_OPERATORS.include?(operator) }
        rescue Gem::Requirement::BadRequirementError
          []
        end
        floors.select { |version| version >= NO_FLOOR }.min
      end

      # The lowest released version the CI matrix pins, ignoring entries such as
      # "head" or "truffleruby", and bare majors: setup-ruby reads "3" as the
      # latest 3.x, which proves no particular minor release.
      def lowest_release(versions)
        versions.select { |v| Gem::Version.correct?(v) && v.include?(".") }.map { |v| Gem::Version.new(v) }.min
      end

      # Support is claimed per minor release, so compare major.minor only.
      def minor(version) = Gem::Version.new(version.segments.first(2).join("."))
    end
  end
end
