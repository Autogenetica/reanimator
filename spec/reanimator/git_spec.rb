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
      expect(identity("evil.example:x@github.com:org/widget.git")).not_to eq(identity("git@github.com:org/widget.git"))
      expect(identity("git@github.com.evil.example:org/widget.git")).not_to eq(identity("git@github.com:org/widget.git"))
      expect(identity("https://github.com.evil.example/org/widget")).not_to eq(identity("https://github.com/org/widget"))
    end
  end

  describe ".remote_identity everywhere else" do
    it "compares the remote exactly, apart from whitespace and a trailing slash" do
      expect(identity(" git@gitserver:/srv/widget/ ")).to eq("=git@gitserver:/srv/widget")
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
