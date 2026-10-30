# frozen_string_literal: true

# Drift trusts this identity to decide that two snapshots describe one
# repository. The dangerous direction is collapsing two repositories into one,
# which reports "no drift" against someone else's contract - so every case
# that must stay distinct is pinned here, not just the ones that must match.
RSpec.describe Reanimator::Git do
  def identity(url) = described_class.remote_identity(url)

  describe ".remote_identity" do
    it "names one GitHub repository the same over SSH, HTTPS, ssh:// and with a CI token" do
      ids = [
        "git@github.com:Autogenetica/reanimator.git",
        "https://github.com/Autogenetica/reanimator",
        "https://x-access-token:abc@github.com/Autogenetica/reanimator.git/", # trufflehog:ignore - fake credential fixture
        "ssh://git@github.com:22/Autogenetica/reanimator.git"
      ].map { |url| identity(url) }

      expect(ids.uniq).to eq(["github.com/autogenetica/reanimator"])
    end

    it "keeps numeric owners in scp-like remotes, which never carry a port" do
      expect(identity("git@github.com:1234/widget.git")).not_to eq(identity("git@github.com:5678/widget.git"))
      expect(identity("git@github.com:1234/widget.git")).to eq("github.com/1234/widget")
    end

    it "keeps non-default ports, which can be separate forge instances" do
      expect(identity("ssh://git@host:2222/org/repo")).not_to eq(identity("ssh://git@host:2223/org/repo"))
      expect(identity("https://host:8443/org/repo")).not_to eq(identity("https://host:9443/org/repo"))
    end

    it "folds path case only on forges whose paths are case-insensitive" do
      expect(identity("git@GitHub.com:Org/Repo.git")).to eq(identity("https://github.com/org/repo"))
      expect(identity("git@git.example.com:/srv/git/Repo.git")).not_to eq(identity("git@git.example.com:/srv/git/repo.git"))
    end

    it "keeps GitLab subgroups" do
      expect(identity("git@gitlab.com:group/sub/project.git")).to eq("gitlab.com/group/sub/project")
    end

    it "compares local paths and file URLs exactly, in a namespace no remote can reach" do
      expect(identity("/srv/A")).to eq("raw:/srv/A")
      expect(identity("file:///srv/A")).not_to eq(identity("file:///srv/a"))
      expect(identity("file://host/srv/Repo")).not_to eq(identity("ssh://host/srv/Repo"))
      expect(identity("github.com/org/repo")).not_to eq(identity("git@github.com:org/repo"))
      expect(identity("  /srv/A  ")).to eq("raw:/srv/A")
    end

    it "keeps the SSH user off the forges, where it selects whose home the path is in" do
      expect(identity("alice@gitserver:widget.git")).not_to eq(identity("bob@gitserver:widget.git"))
      expect(identity("ssh://alice@h/~/repo")).not_to eq(identity("ssh://bob@h/~/repo"))
    end

    it "tells an absolute path from a home-relative one, and matches the same absolute path either way" do
      expect(identity("git@gitserver:srv/widget.git")).not_to eq(identity("ssh://git@gitserver/srv/widget.git"))
      expect(identity("git@gitserver:/srv/widget.git")).to eq(identity("ssh://git@gitserver/srv/widget.git"))
    end

    it "ignores credentials in HTTP userinfo off the forges" do
      expect(identity("https://ci:token@git.example.com/team/app")).to eq(identity("https://git.example.com/team/app")) # trufflehog:ignore - fake credential fixture
    end

    it "treats each scheme's default port as no port" do
      expect(identity("git://host:9418/org/repo")).to eq(identity("git://host/org/repo"))
      expect(identity("http://host:80/org/repo")).to eq(identity("http://host/org/repo"))
    end

    it "lowercases hosts and treats all three forges as case-insensitive" do
      expect(identity("https://GitHub.COM/org/repo")).to eq("github.com/org/repo")
      expect(identity("git@gitlab.com:Group/Repo.git")).to eq("gitlab.com/group/repo")
      expect(identity("git@bitbucket.org:Team/Repo.git")).to eq("bitbucket.org/team/repo")
    end

    it "does not read an scp path that begins with // as a URL" do
      expect(identity("host://path")).to eq("raw:host://path")
    end

    it "treats a trailing slash on an scp remote as the same repository" do
      expect(identity("git@github.com:org/repo/")).to eq(identity("git@github.com:org/repo"))
      expect(identity(" git@github.com:org/repo ")).to eq("github.com/org/repo")
    end
  end
end
