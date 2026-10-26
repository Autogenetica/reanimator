# frozen_string_literal: true

module Reanimator
  # A credentialed provider integration available to an account or organization
  # (specification section 08 credential model). Credentials are connected at
  # the account level and **never committed to a repository** - this object
  # holds only a *reference* to where the secret lives (an environment variable
  # name), plus the policy envelope the connection operates within: which
  # repositories it may touch, its code-egress posture, its budget, models, and
  # execution mode.
  class AgentConnection
    # Code-egress postures a connection can declare.
    EGRESS = %i[none approved_providers any].freeze
    EXECUTION_MODES = %i[hosted local].freeze

    attr_reader :provider, :display_name, :credentials_ref, :permitted_repositories,
      :code_egress, :max_cost_usd, :models, :tools, :execution_mode

    def initialize(provider:, credentials_ref: nil, display_name: nil, permitted_repositories: ["*"],
      code_egress: :approved_providers, max_cost_usd: 8.0, models: [], tools: [], execution_mode: :hosted)
      @provider = provider.to_sym
      @display_name = display_name || @provider.to_s
      @credentials_ref = credentials_ref
      @permitted_repositories = Array(permitted_repositories)
      @code_egress = code_egress.to_sym
      @max_cost_usd = max_cost_usd
      @models = Array(models)
      @tools = Array(tools)
      @execution_mode = execution_mode.to_sym
      validate!
    end

    # A local, self-hosted connection: no credentials, no egress, code and
    # execution stay on user-controlled runners (section 12 "local" posture).
    def self.local(**overrides)
      new(provider: :local, code_egress: :none, execution_mode: :local,
        display_name: "Local rule-based agent", **overrides)
    end

    def local? = execution_mode == :local || provider == :local

    # Whether this connection is permitted to act on a repository full name.
    def permits?(full_name)
      permitted_repositories.any? { |glob| File.fnmatch?(glob, full_name.to_s, File::FNM_PATHNAME) }
    end

    def to_h
      {
        provider: provider, display_name: display_name, credentials_ref: credentials_ref,
        permitted_repositories: permitted_repositories, code_egress: code_egress,
        max_cost_usd: max_cost_usd, models: models, execution_mode: execution_mode
      }
    end

    private

    def validate!
      raise UnknownError, "Unknown code_egress #{code_egress.inspect}." unless EGRESS.include?(code_egress)
      raise UnknownError, "Unknown execution_mode #{execution_mode.inspect}." unless EXECUTION_MODES.include?(execution_mode)
    end
  end
end
