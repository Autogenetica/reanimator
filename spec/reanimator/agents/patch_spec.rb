# frozen_string_literal: true

RSpec.describe Reanimator::Agents::Patch do
  it "writes edits beneath a root" do
    dir = make_repo
    described_class.write("lib/calc.rb", "ok").apply(dir)
    expect(File.read(File.join(dir, "lib/calc.rb"))).to eq("ok")
  end

  it "deletes files marked for deletion" do
    dir = make_repo(files: {"stale.rb" => "x"})
    patch = described_class.new([described_class::Edit.new(path: "stale.rb", delete: true)])
    patch.apply(dir)
    expect(File.exist?(File.join(dir, "stale.rb"))).to be(false)
  end

  it "refuses to escape the workspace root" do
    dir = make_repo
    expect { described_class.write("../escape.rb", "x").apply(dir) }
      .to raise_error(Reanimator::PolicyViolation, /escapes/)
  end

  it "reports its paths and emptiness" do
    expect(described_class.new).to be_empty
    expect(described_class.write("a.rb", "x").paths).to eq(["a.rb"])
  end
end
