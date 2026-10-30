# frozen_string_literal: true

# Drift trusts this identity to decide that two snapshots describe one
# repository. The dangerous direction is collapsing two repositories into one,
# which reports "no drift" against someone else's contract. So only the known
# forges are normalised, parsed strictly the way git reads them; every other
# remote is compared exactly. Every pair that must stay distinct is pinned here,
# not just the ones that must match.
RSpec.describe Reanimator::Git do
  def identity(url) = described_class.remote_identity(url)

  describe ".remote_identity on the known forges" do
    it "names one GitHub repository the same over SSH, HTTPS, ssh:// and with a CI token" do
      ids = [
        "git@github.com:Autogenetica/reanimator.git",
        "https://github.com/Autogenetica/reanimator",
        "https://x-access-token:abc@github.com/Autogenetica/reanimator.git/", # trufflehog:ignore - fake credential fixture
        "ssh://git@github.com:22/Autogenetica/reanimator.git",
        "HTTPS://GitHub.COM/Autogenetica/Reanimator",
        " git@github.com:Autogenetica/reanimator "
      ].map { |url| identity(url) }

      expect(ids.uniq).to eq(["github.com/autogenetica/reanimator"])
    end

    it "keeps numeric owners in scp-like remotes, which never carry a port" do
      expect(identity("git@github.com:1234/widget.git")).to eq("github.com/1234/widget")
      expect(identity("git@github.com:1234/widget.git")).not_to eq(identity("git@github.com:5678/widget.git"))
    end

    it "treats GitLab and Bitbucket the same way, keeping GitLab subgroups" do
      expect(identity("git@gitlab.com:Group/Sub/Project.git")).to eq("gitlab.com/group/sub/project")
      expect(identity("https://bitbucket.org/Team/Repo")).to eq("bitbucket.org/team/repo")
    end

    it "does not take another host for a forge" do
      github = identity("git@github.com:org/repo.git")
      [
        "evil.example:x@github.com:org/repo.git",
        "evil.example:git@github.com:org/repo.git",
        "http://github.com/org/repo",
        "ssh://bob@github.com/org/repo",
        "bob@github.com:org/repo",

        "git@github.com.evil.example:org/repo.git",
        "https://github.com.evil.example/org/repo",
        "[evil.example]x@github.com:org/repo",
        "[evil.example]@github.com:org/repo",
        "ssh://[evil.example]@github.com/org/repo",
        "ssh://[evil.example:2222]@github.com/org/repo",
        'https://evil.example#@github.com/org/repo',
        "https://evil.example?@github.com/org/repo",
        "http://localhost:8000?@github.com/org/repo",
        "ssh://git@github.com:2222/org/repo",
        "https://github.com:8443/org/repo"
      ].each { |remote| expect(identity(remote)).not_to eq(github), remote }
    end

    it "compares a single-segment path or a non-ASCII spelling exactly, never as a forge" do
      ["git@github.com:repo", "git@bitbuc\u212Aet.org:org/repo"].each do |remote|
        expect(identity(remote)).to start_with("="), remote
      end
    end

    it "accepts only allow-listed characters in userinfo, so nothing can redirect the host" do
      ["[", "]", "?", "#", "\\", " ", "/", "@"].each do |char|
        expect(identity("https://evil#{char}x@github.com/org/repo")).to start_with("="), char.inspect
      end
      expect(identity("https://x-access-token:ghs_abc123@github.com/org/repo")).to eq("github.com/org/repo") # trufflehog:ignore - fake credential fixture
    end

    it "never folds . or .. path segments, which transports resolve differently" do
      expect(identity("https://github.com/octocat/x/../Hello-World")).to start_with("=")
      expect(identity("https://github.com/org/.github")).to eq("github.com/org/.github")
    end
  end

  describe ".remote_identity everywhere else" do
    it "compares the remote exactly, apart from surrounding whitespace" do
      expect(identity(" git@gitserver:/srv/widget ")).to eq("=git@gitserver:/srv/widget")
      expect(identity("gitserver:/")).not_to eq(identity("gitserver:"))
    end

    it "keeps every part that can name a different repository off the forges" do
      [
        ["gitserver:/srv/git/widget", "gitserver:/srv/git/widget.git"],
        ["alice@gitserver:widget.git", "bob@gitserver:widget.git"],
        ["git@gitserver:srv/widget.git", "git@gitserver:/srv/widget.git"],
        ["ssh://git@host:2222/org/repo", "ssh://git@host:2223/org/repo"],
        ["git@git.example.com:/srv/git/Repo.git", "git@git.example.com:/srv/git/repo.git"],
        ["file:///srv/A", "file:///srv/a"]
      ].each do |one, other|
        expect(identity(one)).not_to eq(identity(other)), "#{one} vs #{other}"
      end
    end

    it "keeps local paths and look-alike aliases apart from each other and from forge remotes" do
      expect(identity("/srv/a")).not_to eq(identity("raw:/srv/a"))
      expect(identity("github.com/org/repo")).not_to eq(identity("git@github.com:org/repo"))
    end

    it "refuses a self-hosted forge reached over a different transport - the safe direction" do
      expect(identity("git@gitlab.company.com:org/repo.git")).not_to eq(identity("https://gitlab.company.com/org/repo.git"))
    end
  end
end
