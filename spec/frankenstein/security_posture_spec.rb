# frozen_string_literal: true

RSpec.describe Frankenstein::SecurityPosture do
  it "makes security evidence binding under strict and merely visible under balanced" do
    expect(described_class[:strict].required_controls)
      .to contain_exactly(:security_policy, :dependency_review, :secret_scanning)
    expect(described_class[:balanced].required_controls).to be_empty
    expect(described_class[:balanced].advisory_controls)
      .to contain_exactly(:dependency_review, :secret_scanning, :security_policy)
  end

  it "requires secret scanning on local runners, where committed secrets still leak" do
    expect(described_class[:local].required_controls).to eq([:secret_scanning])
  end

  it "implies nothing under custom, because a preset must not relax silently in either direction" do
    expect(described_class[:custom].obligations).to be_empty
  end

  it "defaults private repositories to the posture that blocks" do
    expect(described_class.default_for("private").required_controls).not_to be_empty
    expect(described_class.default_for("public").required_controls).to be_empty
  end

  it "refuses an unknown posture by name" do
    expect { described_class[:permissive] }
      .to raise_error(Frankenstein::UnknownError, /Unknown security posture/)
  end
end
