# frozen_string_literal: true

module Reanimator
  module Agents
    # The contract every coding-agent provider implements (specification
    # section 08). Keeping this surface tiny is the whole point: swapping
    # providers must never require redefining acceptance criteria, so an
    # adapter only ever *enumerates capabilities* and *proposes a repair* - it
    # does not grade, merge, or decide policy.
    class Adapter
      # @return [AgentConnection]
      attr_reader :connection

      def initialize(connection)
        @connection = connection
      end

      # @return [Symbol] provider name
      def provider = connection.provider

      # @return [Boolean] whether the adapter can actually run right now
      #   (credentials present and integration available)
      def available?
        raise NotImplementedError, "#{self.class} must implement #available?"
      end

      # @return [Array<Symbol>] the {Capability} values this adapter offers
      def capabilities
        raise NotImplementedError, "#{self.class} must implement #capabilities"
      end

      # @param capability [Symbol]
      def supports?(capability) = capabilities.include?(capability.to_sym)

      # The provider's code-egress posture, inherited from the connection.
      def code_egress = connection.code_egress

      # Attempt a repair. Returns an untrusted {Result}; never applies it.
      # @param task [RepairTask]
      # @return [Result]
      def repair(task)
        raise NotImplementedError, "#{self.class} must implement #repair"
      end

      # @return [String, nil] why the adapter is unavailable, for reporting
      def unavailable_reason = nil
    end
  end
end
