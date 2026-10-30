# frozen_string_literal: true

module Reanimator
  # One thing a human should see (specification section 16): how serious it is,
  # what it concerns, and what is wrong. Baselines and runs each say what their
  # findings are, so the surfaces that deliver them - annotations, summaries -
  # never need to know which kind of subject they came from.
  #
  # level   - :error when it blocks (and changes the exit status), :notice when
  #           it is advisory; the names are GitHub's annotation levels
  # title   - what it concerns, e.g. "acme/widget support_matrix"
  # message - what is wrong
  Finding = Data.define(:level, :title, :message) do
    def self.levels = %i[error notice]

    def initialize(level:, title:, message:)
      raise UnknownError, "Unknown finding level #{level.inspect}." unless self.class.levels.include?(level)

      super
    end

    def blocking? = level == :error
  end
end
