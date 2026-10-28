# frozen_string_literal: true

# Section 11 submit rung. The submitter is the only thing that holds the
# credential, and it opens a draft only for the exact tree that was verified.
# Every example uses FakeGitHub: the suite never submits anything.
RSpec.describe Reanimator::Submitter do
  def checkout(origin: "git@github.com:acme/widget.git")
    path = make_repo(files: {"lib/calc.rb" => "old\n"}, git: true)
    system("git", "-C", path, "remote", "add", "origin", origin, out: File::NULL, err: File::NULL) if origin
    path
  end

  def head_of(path) = Reanimator::Git.head_sha(path)

  def change
    target = Reanimator::AcceptanceCriterion.new(id: :arithmetic, claim: "add(2, 2) equals 4.", evaluator: :command)
    Reanimator::ProposedChange.new(
      obligation: Reanimator::Obligation.new(repository: nil, policy_version: "generic@abc", target: target,
        trigger: "user request", task_class: :patch_dependency),
      patch: Reanimator::Agents::Patch.write("lib/calc.rb", "new\n"),
      plan: "Use addition.", pre_state: :at_risk, post_state: :alive
    )
  end

  def submitter_for(path, github) = described_class.new(Reanimator::Repository.at(path), client: github)

  it "opens a draft pull request holding exactly the patch, on top of the verified head" do
    path = checkout
    github = FakeGitHub.new(head: head_of(path))

    outcome = submitter_for(path, github).submit(change)

    expect(outcome).to be_submitted
    expect(outcome.url).to eq("https://github.com/acme/widget/pull/7")
    expect(github.posted("/git/trees")).to eq(base_tree: "base-tree",
      tree: [{path: "lib/calc.rb", mode: "100644", type: "blob", content: "new\n"}])
    expect(github.posted("/git/commits")).to include(parents: [head_of(path)], tree: "new-tree")
    expect(github.posted("/git/refs")).to eq(ref: "refs/heads/#{change.branch}", sha: "new-commit")
    expect(github.posted("/pulls")).to include(draft: true, head: change.branch, base: "main", body: change.body)
  end

  it "moves the existing branch and updates the open pull request instead of duplicating either" do
    path = checkout
    open_pull = {"number" => 3, "html_url" => "https://github.com/acme/widget/pull/3"}
    github = FakeGitHub.new(head: head_of(path), branch_exists: true, open_pull: open_pull)

    outcome = submitter_for(path, github).submit(change)

    expect(outcome.url).to eq("https://github.com/acme/widget/pull/3")
    expect(github.patched("/git/refs/heads/")).to eq(sha: "new-commit", force: true)
    expect(github.patched("/pulls/3")).to include(title: change.title)
    expect(github.posted("/pulls")).to be_nil
  end

  it "flags elevated review in the title and body" do
    path = checkout
    github = FakeGitHub.new(head: head_of(path))

    submitter_for(path, github).submit(change, elevated_review: true)

    expect(github.posted("/pulls")[:title]).to start_with("[elevated review] ")
    expect(github.posted("/pulls")[:body]).to include("Elevated review.")
  end

  it "refuses when the remote default branch is not the commit that was verified" do
    path = checkout
    github = FakeGitHub.new(head: "f" * 40)

    outcome = submitter_for(path, github).submit(change)

    expect(outcome).not_to be_submitted
    expect(outcome.reason).to include("would not contain the tree that was verified")
    expect(github.posted("/git/trees")).to be_nil
  end

  it "refuses a dirty working tree, because what was verified is not what is committed" do
    path = checkout
    File.write(File.join(path, "lib/calc.rb"), "edited locally\n")
    github = FakeGitHub.new(head: head_of(path))

    outcome = submitter_for(path, github).submit(change)

    expect(outcome.reason).to include("uncommitted changes")
    expect(github.calls).to be_empty
  end

  it "refuses without a token, and never builds a client" do
    path = checkout
    outcome = described_class.new(Reanimator::Repository.at(path), token: nil).submit(change)

    expect(outcome.reason).to include("REANIMATOR_GITHUB_TOKEN")
  end

  it "refuses a repository with no GitHub owner/name" do
    path = checkout(origin: nil)
    outcome = submitter_for(path, FakeGitHub.new(head: head_of(path))).submit(change)

    expect(outcome.reason).to include("is not an owner/name GitHub repository")
  end

  it "turns a GitHub refusal into a reason rather than an exception" do
    path = checkout
    github = FakeGitHub.new(head: head_of(path))
    allow(github).to receive(:post).and_raise(Reanimator::GitHubClient::Error.new("Resource not accessible", status: 403))

    outcome = submitter_for(path, github).submit(change)

    expect(outcome.reason).to include("Resource not accessible")
  end
end
