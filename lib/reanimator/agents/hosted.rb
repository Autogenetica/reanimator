# frozen_string_literal: true

module Reanimator
  module Agents
    # A placeholder for hosted providers (Codex, Claude, Amp). It declares the
    # capabilities such a provider would offer so routing and reports can reason
    # about it, but it is honest that no hosted integration ships in this slice:
    # it reports itself unavailable rather than pretending to run. A real
    # adapter - potentially backed by the codenamev/agentic orchestrator -
    # implements #repair by calling its model and returns the same {Result}.
    class Hosted < Adapter
      def available? = false

      def capabilities
        [Capability::PLAN, Capability::PATCH, Capability::REPOSITORY_EDIT,
          Capability::SANDBOX_EXEC, Capability::NETWORK]
      end

      def credentialed?
        ref = connection.credentials_ref
        ref && !ENV[ref].to_s.empty?
      end

      def unavailable_reason
        if credentialed?
          "Credentials are present, but the #{provider} hosted adapter is not implemented in this version."
        else
          "No credentials found#{" (set #{connection.credentials_ref})" if connection.credentials_ref}; " \
            "connect the #{provider} provider first."
        end
      end

      def repair(_task)
        raise Error, "The #{provider} adapter cannot run a repair: #{unavailable_reason}"
      end
    end
  end
end
