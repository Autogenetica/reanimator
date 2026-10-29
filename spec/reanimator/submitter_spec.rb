# frozen_string_literal: true

# Section 11 submit rung, second step. The submitter reads a proposal and talks
# to the GitHub API - no repository code, no git - and ships only the verified
# tree without ever overwriting people. Every example uses FakeGitHub: the
# suite never submits anything.
SUBMIT_BASE = "a" * 40

RSpec.describe Reanimator::Submitter do
  def proposal(**overrides)
    defaults = {
      host: "github.com", slug: "acme/widget", base: SUBMIT_BASE, branch: "reanimator/repair-arithmetic-1a2b3c4d",
      title: "Fix: add(2, 2) equals 4.", body: "Verified.", elevated_review: false, blocker: nil,
      edits: [{path: "lib/calc.rb", mode: "100644", contents: "new\n"}]
    }
    Reanimator::Proposal.new(**defaults, **overrides)
  end

  def submit(github, **overrides) = described_class.new(client: github).submit(proposal(**overrides))

  it "opens a draft pull request holding exactly the proposal, on top of the verified head" do
    github = FakeGitHub.new(head: SUBMIT_BASE)

    outcome = submit(github)

    expect(outcome).to be_submitted
    expect(outcome.url).to eq("https://github.com/acme/widget/pull/7")
    expect(github.posted("/git/trees")).to eq(base_tree: "base-tree",
      tree: [{path: "lib/calc.rb", mode: "100644", type: "blob", content: "new\n"}])
    expect(github.posted("/git/commits")).to include(parents: [SUBMIT_BASE], tree: "new-tree")
    expect(github.posted("/git/commits")[:message]).to end_with(described_class::TRAILER)
    expect(github.posted("/git/refs")).to eq(ref: "refs/heads/reanimator/repair-arithmetic-1a2b3c4d", sha: "new-commit")
    expect(github.posted("/pulls")).to include(draft: true, head: "reanimator/repair-arithmetic-1a2b3c4d", base: "main")
  end

  it "keeps the committed mode and turns deletions into removals" do
    github = FakeGitHub.new(head: SUBMIT_BASE)

    submit(github, edits: [
      {path: "exe/widget", mode: "100755", contents: "#!/usr/bin/env ruby\n"},
      {path: "lib/old.rb", mode: "100644", delete: true}
    ])

    expect(github.posted("/git/trees")[:tree]).to eq([
      {path: "exe/widget", mode: "100755", type: "blob", content: "#!/usr/bin/env ruby\n"},
      {path: "lib/old.rb", mode: "100644", type: "blob", sha: nil}
    ])
  end

  it "moves its own branch and updates its own draft instead of duplicating either" do
    open_pull = {"number" => 3, "html_url" => "https://github.com/acme/widget/pull/3", "draft" => true}
    github = FakeGitHub.new(head: SUBMIT_BASE, branch_tip: "Fix\n\n#{described_class::TRAILER}", open_pull: open_pull)

    outcome = submit(github)

    expect(outcome.url).to eq("https://github.com/acme/widget/pull/3")
    expect(github.patched("/git/refs/heads/")).to eq(sha: "new-commit", force: true)
    expect(github.patched("/pulls/3")).to include(title: "Fix: add(2, 2) equals 4.")
    expect(github.posted("/pulls")).to be_nil
    expect(github.posted("/git/refs")).to be_nil
  end

  it "never overwrites a branch carrying commits Reanimator did not write" do
    github = FakeGitHub.new(head: SUBMIT_BASE, branch_tip: "Reviewer's fix-up")

    outcome = submit(github)

    expect(outcome.reason).to include("has commits Reanimator did not write")
    expect(github).not_to be_wrote
  end

  it "never adds commits to a pull request a human marked ready" do
    ready = {"number" => 3, "html_url" => "https://github.com/acme/widget/pull/3", "draft" => false}
    github = FakeGitHub.new(head: SUBMIT_BASE, branch_tip: described_class::TRAILER, open_pull: ready)

    outcome = submit(github)

    expect(outcome.reason).to include("marked ready for review")
    expect(github).not_to be_wrote
  end

  it "refuses when the default branch has moved past the verified commit" do
    github = FakeGitHub.new(head: "f" * 40)

    outcome = submit(github)

    expect(outcome.reason).to include("not the verified #{SUBMIT_BASE[0, 12]}")
    expect(github).not_to be_wrote
  end

  it "says the branch was written when the pull request could not be opened" do
    outcome = submit(FakeGitHub.new(head: SUBMIT_BASE, refuse_pulls: true))

    expect(outcome).not_to be_submitted
    expect(outcome).to be_branch_written
    expect(outcome.reason).to include("Draft pull requests are not supported")
  end

  it "refuses what the contract did not allow, before any call" do
    github = FakeGitHub.new(head: SUBMIT_BASE)

    outcome = submit(github, blocker: "the contract does not enable it")

    expect(outcome.reason).to eq("Submission is not allowed: the contract does not enable it")
    expect(github.calls).to be_empty
  end

  it "refuses an origin that is not github.com" do
    github = FakeGitHub.new(head: SUBMIT_BASE)

    expect(submit(github, host: "gitlab.com").reason).to include("not github.com")
    expect(github.calls).to be_empty
  end

  it "refuses without a token" do
    outcome = described_class.new(token: nil).submit(proposal)

    expect(outcome.reason).to include("REANIMATOR_GITHUB_TOKEN")
    expect(outcome).not_to be_branch_written
  end

  it "flags elevated review in the title and body" do
    github = FakeGitHub.new(head: SUBMIT_BASE)

    submit(github, elevated_review: true)

    expect(github.posted("/pulls")[:title]).to start_with("[elevated review] ")
    expect(github.posted("/pulls")[:body]).to include("Elevated review.")
  end

  it "turns a malformed GitHub response into a reason rather than an exception" do
    github = FakeGitHub.new(head: SUBMIT_BASE)
    allow(github).to receive(:get).and_return({})

    expect(submit(github).reason).to include("GitHub returned an unexpected response")
  end
end
