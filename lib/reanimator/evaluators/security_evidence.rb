# frozen_string_literal: true

module Reanimator
  module Evaluators
    # A native evaluator that grades one security control from discovered
    # evidence (specification section 12). It never asks a repository to adopt
    # a particular tool - any of the control's accepted fingerprints counts -
    # and a control with no evidence is reported as missing rather than
    # quietly passed, which is the whole point of making the posture binding.
    class SecurityEvidence < Base
      def call
        control = SecurityControl.fetch(criterion.target)
        evidence = control.evidence_in(discovery)
        return result(:missing_evidence, detail: control.remedy) unless evidence

        result(:verified, detail: evidence.claim, evidence: evidence.provenance.to_s)
      rescue UnknownError => e
        # A contract naming a control we do not know is a misconfiguration, not
        # a pass: say so, and let the unproven rules keep the repository honest.
        result(:error, detail: e.message)
      end
    end
  end
end
