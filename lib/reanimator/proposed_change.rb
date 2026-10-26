# frozen_string_literal: true

require "digest"

module Reanimator
  # A repair that has been produced and independently verified but **not
  # submitted** (specification section 11 autonomy ladder: repair creates a
  # bounded patch "with no repository write required until submission"). It
  # carries everything a draft pull request would need - branch name, patch,
  # title, and body - so submission becomes a separate, explicitly authorized
  # step rather than a side effect of repair.
  class ProposedChange
    attr_reader :obligation, :patch, :plan, :pre_state, :post_state

    def initialize(obligation:, patch:, plan:, pre_state:, post_state:)
      @obligation = obligation
      @patch = patch
      @plan = plan
      @pre_state = pre_state
      @post_state = post_state
    end

    # A deterministic branch name derived from the obligation and the patch, so
    # the same repair maps to the same branch (idempotence).
    def branch
      slug = obligation.target.id.to_s.gsub(/[^a-z0-9]+/i, "-")
      fingerprint = Digest::SHA256.hexdigest(patch.paths.sort.join(","))[0, 8]
      "reanimator/repair-#{slug}-#{fingerprint}"
    end

    def title
      "Fix: #{obligation.target.claim}"
    end

    def body
      <<~BODY.strip
        Reanimator proposes this bounded repair for `#{obligation.target.id}`.

        Objective: #{obligation.target.claim}
        Result: #{pre_state} → #{post_state} (independently verified)
        Files: #{patch.paths.join(", ")}

        #{plan}

        This change was produced by an isolated agent and graded by Reanimator's
        own evaluators; the agent did not grade its own work. Merge remains a
        human decision.
      BODY
    end

    def to_h
      {branch: branch, title: title, files: patch.paths, pre_state: pre_state, post_state: post_state}
    end
  end
end
