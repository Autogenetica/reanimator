# frozen_string_literal: true

module Reanimator
  # How strongly a discovered fact is believed, and - just as importantly -
  # what the product is allowed to do with that belief (specification section
  # 06). Confidence never silently becomes authority: even a high-confidence
  # fact is only *preselected*, and it still asks for confirmation when it
  # would affect permissions, cost, privacy, or action authority.
  class Confidence
    include Comparable

    LEVELS = %i[low medium high].freeze

    BEHAVIOR = {
      high: "Preselect and ask for confirmation only when the fact affects " \
            "permissions, cost, privacy, or action authority.",
      medium: "Show as a suggestion with evidence and alternatives.",
      low: "Use to prioritize a question; never convert directly into an obligation."
    }.freeze

    attr_reader :level

    def initialize(level)
      @level = level.to_sym
      unless LEVELS.include?(@level)
        raise UnknownError, "Unknown confidence #{level.inspect}. Known: #{LEVELS.join(", ")}."
      end
      freeze
    end

    HIGH = new(:high)
    MEDIUM = new(:medium)
    LOW = new(:low)

    def self.[](level)
      case level
      when Confidence then level
      when :high, "high" then HIGH
      when :medium, "medium" then MEDIUM
      when :low, "low" then LOW
      else new(level)
      end
    end

    # Product behavior mandated for this confidence level.
    # @return [String]
    def behavior = BEHAVIOR.fetch(level)

    # High-confidence facts may be preselected in the review UI; lower ones may
    # only be suggested or used to prioritize a question.
    def preselectable? = level == :high

    # A low-confidence fact must never be converted directly into an
    # obligation - it can only shape a question.
    def obligatable? = level != :low

    def <=>(other)
      return nil unless other.is_a?(Confidence)
      LEVELS.index(level) <=> LEVELS.index(other.level)
    end

    def to_sym = level

    def to_s = level.to_s
  end
end
