# frozen_string_literal: true

RSpec.describe Reanimator::AgentConnection do
  it "builds a local connection with no egress and no credentials" do
    connection = described_class.local
    expect(connection).to be_local
    expect(connection.code_egress).to eq(:none)
    expect(connection.credentials_ref).to be_nil
  end

  it "scopes permitted repositories by glob" do
    connection = described_class.new(provider: :codex, permitted_repositories: ["codenamev/*"])
    expect(connection.permits?("codenamev/widget")).to be(true)
    expect(connection.permits?("someone/else")).to be(false)
  end

  it "references credentials rather than holding them" do
    connection = described_class.new(provider: :codex, credentials_ref: "OPENAI_ACCESS_TOKEN")
    expect(connection.credentials_ref).to eq("OPENAI_ACCESS_TOKEN")
    expect(connection.to_h).not_to have_key(:credentials)
  end

  it "rejects an unknown egress posture" do
    expect { described_class.new(provider: :codex, code_egress: :wide_open) }
      .to raise_error(Reanimator::UnknownError, /egress/)
  end
end
