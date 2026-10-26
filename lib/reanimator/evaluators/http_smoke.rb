# frozen_string_literal: true

module Reanimator
  module Evaluators
    # A boot smoke test against a health endpoint. Actually booting a service
    # requires a running environment the read-only baseline deliberately does
    # not provision, so this evaluator records the gap honestly - the criterion
    # is a real, valuable proof-of-life check, it is simply not yet established.
    # This is exactly the "production boot proof not established" gap Appendix A
    # reports as Unproven rather than green.
    class HttpSmoke < Base
      def call
        result(:missing_evidence,
          detail: "Boot smoke against #{criterion.target || "the health endpoint"} needs a running " \
                  "service; not established in a read-only baseline.")
      end
    end
  end
end
