# frozen_string_literal: true

RSpec.describe Reanimator::Containment do
  let(:root) { make_repo(files: {"docs/a.md" => "a"}) }

  def link(name, target) = File.symlink(target, File.join(root, name)).then { File.join(root, name) }

  it "keeps the root, its files, and links to files inside it - written yet or not" do
    expect(described_class.inside?(root, root)).to be(true)
    expect(described_class.inside?(root, File.join(root, "docs/a.md"))).to be(true)
    expect(described_class.inside?(root, link("a", "docs/a.md"))).to be(true)
    expect(described_class.inside?(root, link("later", "docs/later.md"))).to be(true)
  end

  it "refuses what leads out - including a sibling whose name extends the root's - or does not resolve" do
    FileUtils.mkdir_p("#{root}-evil")
    expect(described_class.inside?(root, link("sibling", "#{root}-evil/x"))).to be(false)
    expect(described_class.inside?(root, link("up", "../elsewhere"))).to be(false)
    expect(described_class.inside?(root, link("missing_dir", "nowhere/x"))).to be(false)
  end

  it "passes a path that does not exist, and names the repository when it refuses" do
    expect { described_class.ensure_inside!(root, File.join(root, "absent.yml"), "absent.yml") }.not_to raise_error
    expect { described_class.ensure_inside!(root, link("out.yml", "../out.yml"), "out.yml") }
      .to raise_error(Reanimator::ContractError, /out\.yml in #{Regexp.escape(root)} leads outside/)
  end
end
