# frozen_string_literal: true

RSpec.describe Reanimator::Profiles do
  it "registers the Ruby-first profile set" do
    expect(described_class.ids).to include(:"ruby-gem", :"rails-app", :"rails-legacy", :generic)
  end

  it "resolves inherited criteria most-specific-wins" do
    rails = described_class.fetch(:"rails-app").resolved_criteria.map(&:id)
    # boot is inherited from web-application; tests/assets are rails-app's own.
    expect(rails).to include(:boot, :tests, :assets)
  end

  it "de-duplicates inherited criteria by id" do
    ids = described_class.fetch(:"ruby-cli").resolved_criteria.map(&:id)
    expect(ids).to eq(ids.uniq)
    expect(ids).to include(:tests, :build, :executable)
  end

  it "raises on an unknown profile" do
    expect { described_class.fetch(:cobol) }.to raise_error(Reanimator::UnknownError)
  end
end
