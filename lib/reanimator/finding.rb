# frozen_string_literal: true

module Reanimator
  # One thing a human should see (specification section 16): how serious it is,
  # what it concerns, and what is wrong. Baselines and runs each say what their
  # findings are, so the surfaces that deliver them - annotations, summaries -
  # never need to know which kind of subject they came from.
  #
  # level   - :error when it blocks (and changes the exit status), :notice when
  #           it is advisory
  # title   - what it concerns, e.g. "acme/widget support_matrix"
  # message - what is wrong
  Finding = Struct.new(:level, :title, :message) do
    def blocking? = level == :error
  end
end
