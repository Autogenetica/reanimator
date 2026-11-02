# frozen_string_literal: true

RSpec.describe Reanimator::Isolation do
  def links_in(copy)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: copy).select { |path| File.symlink?(File.join(copy, path)) }
  end

  it "copies links that stay inside the repository, and leaves out every link that leads out" do
    allow(Reanimator.logger).to receive(:warn)
    outside = make_repo(files: {"outside_spec.rb" => "raise 'outside'\n"})
    root = make_repo(files: {"docs/README.md" => "inside", "spec/real_spec.rb" => "true\n", "~/a/.keep" => "", ".github/x/.keep" => ""})
    {
      "README.md" => "docs/README.md",
      "fixtures" => outside,
      "shared" => "../#{File.basename(outside)}",
      "docs/up" => "../../#{File.basename(outside)}",
      ".github/x/out" => outside,
      "escape" => "docs/..",
      "docs/root" => "/",
      "through" => "docs/root/..",
      "dangling" => "nowhere",
      "build" => File.join(root, "build"), # absolute, and not there yet: a write through it would reach the original
      "gone" => "../not-there-yet",
      "home" => "~/a",
      "user" => "~nosuchuser/x", # a missing directory, not a home: no telling where a write would land
      "l" => ".",
      "sneaky" => "#{"l/" * 30}#{"../" * 30}#{root.delete_prefix("/")}/PWNED", # inside as written, out in fact
      "loop_a" => "loop_b",
      "loop_b" => "loop_a",
      "not_a_dir" => "docs/README.md/x"
    }.each { |link, target| File.symlink(target, File.join(root, link)) }

    described_class.copy(root) do |copy|
      expect(links_in(copy)).to contain_exactly("README.md", "escape", "dangling", "home", "l")
      expect(File.read(File.join(copy, "README.md"))).to eq("inside")
      expect(File.directory?(File.join(copy, "spec"))).to be(true)
    end
    expect(Reanimator.logger).to have_received(:warn).with(/Left 13 path\(s\) out .*\.github\/x\/out/)
    expect(File.exist?(File.join(root, "PWNED"))).to be(false)
  end

  it "leaves out a link that climbs back through another link, which a check could turn into a directory" do
    allow(Reanimator.logger).to receive(:warn)
    root = make_repo(files: {"deep/a/b/.keep" => ""})
    File.symlink(".", File.join(root, "l"))
    File.symlink("deep/a/b", File.join(root, "tmp"))
    # Inside as written and in fact - l/tmp is deep/a/b, so this is deep/x.log
    # - but once a check replaces tmp with a directory it is ../x.log.
    File.symlink("l/tmp/../../x.log", File.join(root, "out.log"))
    File.symlink("deep/a/../a/b", File.join(root, "plain_climb"))

    described_class.copy(root) do |copy|
      expect(links_in(copy)).to contain_exactly("l", "tmp", "plain_climb")
    end
  end

  it "leaves out a nested worktree's .git file, which points back at the original repository" do
    allow(Reanimator.logger).to receive(:warn)
    root = make_repo(files: {"worktrees/feature/.git" => "gitdir: /original/.git/worktrees/feature\n", "vendor/lib/.git/HEAD" => "ref\n"})

    described_class.copy(root) do |copy|
      expect(File.exist?(File.join(copy, "worktrees/feature/.git"))).to be(false)
      expect(File.exist?(File.join(copy, "vendor/lib/.git/HEAD"))).to be(true) # a nested repository of its own
    end
    expect(Reanimator.logger).to have_received(:warn).with(%r{worktrees/feature/\.git})
  end

  it "leaves no copy behind when interrupted" do
    allow(FileUtils).to receive(:cp_r).and_raise(Interrupt)
    before = Dir.glob(File.join(Dir.tmpdir, "reanimator-iso*"))

    expect { described_class.copy(make_repo(files: {"a" => "x"})) { nil } }.to raise_error(Interrupt)
    expect(Dir.glob(File.join(Dir.tmpdir, "reanimator-iso*"))).to match_array(before)
  end

  it "leaves no copy behind when copying fails" do
    root = make_repo(files: {"locked/secret" => "x"})
    File.chmod(0o000, File.join(root, "locked"))
    before = Dir.glob(File.join(Dir.tmpdir, "reanimator-iso*"))

    expect { described_class.copy(root) { nil } }.to raise_error(Errno::EACCES)
    expect(Dir.glob(File.join(Dir.tmpdir, "reanimator-iso*"))).to match_array(before)
  ensure
    File.chmod(0o755, File.join(root, "locked")) if root
  end
end
