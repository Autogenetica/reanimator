# frozen_string_literal: true

module Reanimator
  # Coding-agent adapters. The agent is a replaceable life-force adapter
  # (specification section 08): the repository's definition of life is defined
  # by its contract, never by whichever provider happens to perform a repair.
  # Every provider - Codex, Claude, Amp, or a local rule-based agent - speaks
  # the same {Agents::Adapter} contract, so profiles are portable and the
  # acceptance criteria never change when the provider does.
  #
  # This module is the registry and factory. It ships one fully working adapter
  # ({Agents::Local}, a deterministic no-network agent) and stubs for hosted
  # providers that honestly report themselves unavailable until credentials and
  # a real integration exist.
  module Agents
    module_function

    # Built-in adapters keyed by provider name.
    def registry
      {
        local: Local,
        codex: Hosted,
        claude: Hosted,
        amp: Hosted
      }
    end

    # Builds an adapter for a connection.
    # @param connection [AgentConnection]
    # @return [Agents::Adapter]
    def for(connection)
      klass = registry.fetch(connection.provider, Hosted)
      klass.new(connection)
    end

    def providers = registry.keys
  end
end
