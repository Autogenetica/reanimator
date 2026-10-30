# frozen_string_literal: true

module Reanimator
  module Evaluators
    # A boot smoke test against a health endpoint. Actually booting a service
    # requires a running environment Reanimator does not provision yet, so this
    # evaluator records the gap honestly - the criterion is a real, valuable
    # proof-of-life check that is simply not established, which keeps the
    # repository Unproven rather than green (Appendix A's "production boot
    # proof not established").
    #
    # It is *skipped*, not missing evidence: the gap is Reanimator's, not the
    # repository's, so it does not on its own ask a human to act (ADR-009).
    class HttpSmoke < Base
      def call
        result(:skipped,
          detail: "Boot smoke against #{criterion.target || "the health endpoint"} needs a running " \
                  "service, which Reanimator does not provision yet.")
      end
    end
  end
end
