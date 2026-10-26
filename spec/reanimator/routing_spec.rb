# frozen_string_literal: true

RSpec.describe Reanimator::Routing::Router do
  def profile(provider, ready: true, egress: :approved_providers, caps: %i[plan patch repository_edit sandbox_exec], local: false)
    connection = if local
      Reanimator::AgentConnection.local
    else
      Reanimator::AgentConnection.new(provider: provider, code_egress: egress)
    end
    Reanimator::AgentProfile.new(
      connection: connection, capabilities: caps, readiness: ready ? :ready : :unavailable
    )
  end

  let(:local) { profile(:local, local: true, caps: %i[plan patch repository_edit sandbox_exec]) }
  let(:codex) { profile(:codex, caps: %i[plan patch repository_edit sandbox_exec network]) }
  let(:claude) { profile(:claude, caps: %i[plan patch repository_edit sandbox_exec network]) }

  it "auto-selects the local profile first and explains why" do
    decision = described_class.new([codex, local]).select
    expect(decision.provider).to eq(:local)
    expect(decision.explanation).to include("Selected local (auto)")
    expect(decision.explanation).to include("fallback is never implied")
  end

  it "honors a pinned provider" do
    decision = described_class.new([codex, local], strategy: :pinned, pin: :codex).select
    expect(decision.provider).to eq(:codex)
  end

  it "tries an explicit order" do
    decision = described_class.new([codex, claude], strategy: :ordered, order: %i[claude codex]).select
    expect(decision.provider).to eq(:claude)
  end

  it "excludes non-local profiles under local-only" do
    decision = described_class.new([codex, local], strategy: :local_only).select
    expect(decision.provider).to eq(:local)
    expect(decision.excluded.map { |e| e[:provider] }).to include(:codex)
  end

  it "excludes profiles missing a required capability" do
    decision = described_class.new([local, codex]).select(required_capabilities: [:network])
    expect(decision.provider).to eq(:codex)
    expect(decision.excluded.find { |e| e[:provider] == :local }[:reason]).to include("network")
  end

  it "defers under manual routing while observation stays automatic" do
    decision = described_class.new([codex, local], strategy: :manual).select
    expect(decision.selected?).to be(false)
    expect(decision.explanation).to include("manual").and include("Observation and baseline remain automatic")
  end

  it "only offers a declared fallback that shares the data-handling policy" do
    other_local = profile(:local, local: true)
    decision = described_class.new([local], fallback: [codex, other_local]).select
    # codex (approved_providers) differs from local (none) and is excluded as fallback.
    expect(decision.fallbacks.map(&:provider)).to eq([:local])
  end
end
