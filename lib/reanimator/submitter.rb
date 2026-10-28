# frozen_string_literal: true

module Reanimator
  # Opens a verified {ProposedChange} as a draft pull request (specification
  # section 11, the submit rung). It is deliberately separate from every agent,
  # mirroring verifier isolation: an agent proposes a patch and never holds the
  # credential; this component decides whether that patch leaves the machine.
  #
  # It writes nothing locally. The branch is built through the GitHub API on
  # top of the default branch's head, and only when that head is exactly the
  # commit the repair was verified against - otherwise the pull request would
  # contain a tree nobody verified, so it refuses instead. Pull requests are
  # always drafts in v1; merge stays a human decision.
  #
  # Every refusal is an {Outcome} with a reason, never an exception, so the
  # caller can escalate with the verified change still attached.
  class Submitter
    Outcome = Struct.new(:url, :reason) do
      def submitted? = !url.nil?
    end

    SLUG = %r{\A[\w.-]+/[\w.-]+\z}

    ELEVATED_NOTE = "**Elevated review.** This repository's contract includes verifier or " \
                    "contract-touching criteria, so this change needs a reviewer who can judge the " \
                    "rules of proof, not only the code."

    # @param repository [Repository]
    # @param client [#get, #post, #patch, nil] injected in specs; built from
    #   the token otherwise
    # @param token [String, nil]
    def initialize(repository, client: nil, token: ENV[Configuration::GITHUB_TOKEN_ENV])
      @repository = repository
      @client = client || (GitHubClient.new(token: token) unless token.to_s.empty?)
    end

    # @param change [ProposedChange]
    # @param elevated_review [Boolean]
    # @return [Outcome]
    def submit(change, elevated_review: false)
      reason = precondition_failure
      return refused(reason) if reason

      base, head = default_branch_head
      unless head == Git.head_sha(@repository.path)
        return refused("the local checkout is not at #{slug}@#{base} (#{head[0, 12]}), so the pull " \
                       "request would not contain the tree that was verified")
      end

      commit = commit_patch(change, head)
      point_branch(change.branch, commit)
      Outcome.new(open_draft(change, base, elevated_review), nil)
    rescue GitHubClient::Error => e
      refused(e.message)
    end

    private

    def precondition_failure
      return "no GitHub token; set #{Configuration::GITHUB_TOKEN_ENV}" unless @client
      return "#{@repository.full_name.inspect} is not an owner/name GitHub repository" unless SLUG.match?(slug.to_s)
      return "the repository is not a git checkout" unless Git.repository?(@repository.path)
      return if Git.clean?(@repository.path)

      "the working tree has uncommitted changes, so what was verified is not what is committed"
    end

    def slug = @repository.full_name

    def default_branch_head
      base = @client.get("/repos/#{slug}")["default_branch"]
      [base, @client.get("/repos/#{slug}/git/ref/heads/#{base}").dig("object", "sha")]
    end

    # One commit on top of the verified head holding exactly the patch.
    def commit_patch(change, head)
      base_tree = @client.get("/repos/#{slug}/git/commits/#{head}").dig("tree", "sha")
      tree = @client.post("/repos/#{slug}/git/trees", base_tree: base_tree, tree: entries(change.patch))
      @client.post("/repos/#{slug}/git/commits",
        message: change.title, tree: tree["sha"], parents: [head])["sha"]
    end

    def entries(patch)
      patch.edits.map do |edit|
        entry = {path: edit.path, mode: mode(edit.path), type: "blob"}
        edit.delete? ? entry.merge(sha: nil) : entry.merge(content: edit.contents)
      end
    end

    def mode(path)
      File.executable?(File.join(@repository.path, path)) ? "100755" : "100644"
    end

    # The branch name is deterministic per repair, so a repeat run moves the
    # same branch rather than opening a second one.
    def point_branch(branch, commit)
      @client.post("/repos/#{slug}/git/refs", ref: "refs/heads/#{branch}", sha: commit)
    rescue GitHubClient::Error => e
      raise unless e.status == 422

      @client.patch("/repos/#{slug}/git/refs/heads/#{branch}", sha: commit, force: true)
    end

    # Updates the open pull request for the branch if there is one, so a repeat
    # run never duplicates it.
    def open_draft(change, base, elevated_review)
      title = elevated_review ? "[elevated review] #{change.title}" : change.title
      body = elevated_review ? "#{change.body}\n\n#{ELEVATED_NOTE}" : change.body
      owner = slug.split("/").first
      existing = @client.get("/repos/#{slug}/pulls?state=open&head=#{owner}:#{change.branch}").first
      if existing
        @client.patch("/repos/#{slug}/pulls/#{existing["number"]}", title: title, body: body)["html_url"]
      else
        @client.post("/repos/#{slug}/pulls",
          title: title, body: body, head: change.branch, base: base, draft: true)["html_url"]
      end
    end

    def refused(reason) = Outcome.new(nil, reason)
  end
end
