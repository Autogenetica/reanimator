# frozen_string_literal: true

module Frankenstein
  module Evaluators
    # A native evaluator that compares declared runtime support against what CI
    # actually exercises. This is the classic escalation from section 16: "the
    # project declares Ruby 3.2 support, but CI no longer tests it." Declared
    # support with no CI coverage is missing evidence, not a pass.
    class SupportMatrix < Base
      def call
        ci = discovery[:ci_ruby_matrix]
        declared = discovery[:supported_ruby]

        if ci
          result(:verified, detail: "CI exercises Ruby #{Array(ci.value).join(", ")}.")
        elsif declared
          result(:missing_evidence,
            detail: "Ruby #{Array(declared.value).join(", ")} is declared but not exercised in CI.")
        else
          result(:skipped, detail: "No declared runtime support matrix to verify.")
        end
      end
    end
  end
end
