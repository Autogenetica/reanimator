# frozen_string_literal: true

module Reanimator
  # Computes a repository's proof-of-life state from its baseline results and
  # its lifecycle intent (specification section 15). The rules encode two
  # non-negotiables: a failing required check is never green, and a claim
  # without executable evidence is Unproven rather than Alive. Intent shapes
  # the reading - a preserved artifact that proves its integrity is Sleeping,
  # not Alive, because it is intentionally not actively maintained.
  module ProofOfLife
    module_function

    # @param contract [EffectiveContract]
    # @param results [Array<CriterionResult>]
    # @return [RepositoryState]
    def assess(contract, results)
      required = results.select(&:required?)
      failed = required.select(&:failed?)
      unproven = required.select(&:unproven?)
      intent = contract.intent.to_sym

      RepositoryState.fetch(state_key(intent, failed, unproven))
    end

    def state_key(intent, failed, unproven)
      return :retired if intent == :retire

      if failed.any?
        :at_risk
      elsif unproven.any?
        (intent == :upstream) ? :sleeping : :unproven
      else
        proven_state(intent)
      end
    end

    # State for a repository whose required criteria are all verified.
    def proven_state(intent)
      case intent
      when :maintain, :incubate then :alive
      else :sleeping # monitor, preserve, upstream, ignore
      end
    end
  end
end
