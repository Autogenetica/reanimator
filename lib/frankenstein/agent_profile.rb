# frozen_string_literal: true

module Frankenstein
  # A policy-constrained execution configuration for one provider, model,
  # sandbox, tool set, and data-handling posture (specification section 02 and
  # section 08). A profile is what commissioning proves *ready*, *degraded*,
  # *incompatible*, or *unavailable* - the readiness verdict is set from a
  # commissioning report, never assumed.
  class AgentProfile
    READINESS = %i[unknown ready degraded incompatible unavailable].freeze

    attr_reader :connection, :model, :sandbox, :data_handling, :capabilities
    attr_accessor :readiness

    def initialize(connection:, model: nil, sandbox: :ephemeral, data_handling: nil,
      capabilities: [], readiness: :unknown)
      @connection = connection
      @model = model || connection.models.first
      @sandbox = sandbox
      @data_handling = data_handling || connection.code_egress
      @capabilities = capabilities
      @readiness = readiness.to_sym
      raise UnknownError, "Unknown readiness #{readiness.inspect}." unless READINESS.include?(@readiness)
    end

    # Builds a profile straight from an adapter, seeding its capabilities.
    def self.from_adapter(adapter, **overrides)
      new(connection: adapter.connection, capabilities: adapter.capabilities, **overrides)
    end

    def supports?(capability) = capabilities.include?(capability.to_sym)

    def provider = connection.provider

    def ready? = readiness == :ready

    # Two profiles share a data-handling policy when their egress posture
    # matches - the precondition for any context transfer during fallback
    # (section 08 fallback rules).
    def same_data_handling?(other)
      data_handling == other.data_handling
    end

    def to_h
      {
        provider: provider, model: model, sandbox: sandbox,
        data_handling: data_handling, readiness: readiness
      }
    end
  end
end
