# frozen_string_literal: true

# Section 11 submit rung, first step. A proposal is made from the committed
# HEAD of a repository root, never the working tree, and records what was
# verified and what the contract allowed - so `submit` can refuse the rest.
PROPOSAL_BROKEN_LIB = "module Calc\n  module_function\n  def add(a, b)\n    a - b\n  end\nend\n"
PROPOSAL_CHECK = %(require "calc"\nraise "broken" unless Calc.add(2, 2) == 4\n)

RSpec.describe "proposing a repair" do
  def contract_yaml(submit: true, extra_checks: "")
    <<~YAML
      version: 1
      intent: maintain
      profile: generic
      autonomy:
        repair: allowed
      #{"  submit: allowed" if submit}
      acceptance:
        protected_paths: [check.rb]
        checks:
          - id: arithmetic
            claim: "add(2, 2) equals 4."
            run: "ruby -Ilib check.rb"
            required: true
      #{extra_checks}
    YAML
  end

  def checkout(files: {}, submit: true, origin: "git@github.com:acme/widget.git")
    root = make_repo(files: {"lib/calc.rb" => PROPOSAL_BROKEN_LIB, "check.rb" => PROPOSAL_CHECK,
                             ".reanimator.yml" => contract_yaml(submit: submit)}.merge(files), git: true)
    system("git", "-C", root, "remote", "add", "origin", origin, out: File::NULL) if origin
    root
  end

  def propose(root) = Reanimator.propose(root, to: File.join(make_repo(files: {}), "proposal.json"))

  it "verifies committed HEAD and records the base commit, contents and modes" do
    root = checkout
    run, written = propose(root)
    proposal = Reanimator::Proposal.load(written)

    expect(run.outcome).to eq(:draft_pr)
    expect(proposal.base).to eq(Reanimator::Git.head_sha(root))
    expect(proposal.slug).to eq("acme/widget")
    expect(proposal.host).to eq("github.com")
    expect(proposal.edits).to eq([{path: "lib/calc.rb", mode: "100644", contents: PROPOSAL_BROKEN_LIB.sub("a - b", "a + b")}])
    expect(proposal).to be_submittable
    expect(File.read(File.join(root, "lib/calc.rb"))).to include("a - b")
  end

  it "ignores uncommitted edits, so a local fix cannot make the proof pass" do
    root = checkout
    File.write(File.join(root, "lib/calc.rb"), PROPOSAL_BROKEN_LIB.sub("a - b", "a + b"))

    run, written = propose(root)

    expect(run.outcome).to eq(:draft_pr)
    expect(run.pre_state).to eq(:at_risk)
    expect(written).not_to be_nil
  end

  it "does not see ignored files that would never be in the pull request" do
    root = checkout(files: {".gitignore" => "lib/calc.rb.local\n"})
    File.write(File.join(root, "lib/calc.rb.local"), "x")
    seen = []
    allow(Reanimator::RepairRun).to receive(:new).and_wrap_original do |original, contract, **kwargs|
      seen << File.exist?(File.join(contract.repository.path, "lib/calc.rb.local"))
      original.call(contract, **kwargs)
    end

    propose(root)

    expect(seen).to eq([false])
  end

  it "records why the contract does not allow submission" do
    _run, written = propose(checkout(submit: false))

    proposal = Reanimator::Proposal.load(written)
    expect(proposal).not_to be_submittable
    expect(proposal.blocker).to include("set autonomy: submit: allowed")
  end

  it "flags elevated review when the contract carries verifier criteria" do
    elevated = <<~YAML.gsub(/^/, "    ")
      - id: workflows
        claim: "CI definitions are intact."
        run: "true"
        required: false
        risk_class: elevated
    YAML
    root = checkout(files: {".reanimator.yml" => contract_yaml(extra_checks: elevated)})

    _run, written = propose(root)

    expect(Reanimator::Proposal.load(written).elevated_review).to be(true)
  end

  it "refuses a path inside a repository, where pull-request paths would point elsewhere" do
    root = checkout
    FileUtils.mkdir_p(File.join(root, "pkg"))

    expect { propose(File.join(root, "pkg")) }.to raise_error(Reanimator::RepositoryError, /propose from the repository root/)
  end

  it "refuses to propose a change through a committed symlink" do
    root = make_repo(files: {"lib/real.rb" => PROPOSAL_BROKEN_LIB, "check.rb" => PROPOSAL_CHECK,
                             ".reanimator.yml" => contract_yaml})
    File.symlink("real.rb", File.join(root, "lib/calc.rb"))
    system("git", "-C", root, "init", "-q", "-b", "main", out: File::NULL)
    system("git", "-C", root, "add", "-A", out: File::NULL)
    system("git", "-C", root, "-c", "user.email=t@e.com", "-c", "user.name=T", "commit", "-qm", "f", out: File::NULL)

    expect { propose(root) }.to raise_error(Reanimator::PolicyViolation, /symlink/)
  end

  it "round-trips through the file it writes, and rejects anything else" do
    _run, written = propose(checkout)
    garbage = File.join(make_repo(files: {"x.json" => "{}"}), "x.json")

    expect(Reanimator::Proposal.load(written).to_h).to eq(JSON.parse(File.read(written), symbolize_names: true))
    expect { Reanimator::Proposal.load(garbage) }.to raise_error(Reanimator::ContractError, /not a Reanimator proposal/)
  end
end
