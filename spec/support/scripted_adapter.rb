# frozen_string_literal: true

# A configurable coding-agent adapter for commissioning specs: it returns a
# canned {Reanimator::Agents::Result} so each verdict path (ready, degraded,
# incompatible, unavailable) can be exercised without a real provider.
class ScriptedAdapter < Reanimator::Agents::Adapter
  def initialize(result:, available: true, capabilities: %i[plan patch repository_edit sandbox_exec])
    super(Reanimator::AgentConnection.local)
    @result = result
    @available = available
    @capabilities = capabilities
  end

  attr_reader :capabilities

  def available? = @available

  def repair(_task) = @result

  def unavailable_reason = "not connected"
end
