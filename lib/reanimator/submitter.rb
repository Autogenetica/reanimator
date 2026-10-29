# frozen_string_literal: true

module Reanimator
  # Opens a {Proposal} as a draft pull request (specification section 11, the
  # submit rung). It is the only reader of the GitHub token, and it runs no
  # repository code and no git: everything it needs is in the proposal, and
  # everything it does is a GitHub API call. That separation is the point -
  # untrusted repository code never shares a process with the credential.
  #
  # It ships only what was verified and never overwrites people:
  # - the default branch must still be at the commit the repair was verified
  #   against, or the pull request would carry an unverified tree;
  # - an existing reanimator/ branch is moved only while its tip is a commit
  #   Reanimator wrote, so work a reviewer pushed there is never discarded;
  # - an open pull request is updated only while it is still a draft, so new
  #   unreviewed commits never land in one a human marked ready.
  #
  # Every refusal is an {Outcome} with a reason, never an exception, and it
  # says whether a branch had already been written.
  class Submitter
    Outcome = Struct.new(:url, :reason, :branch_written) do
      def submitted? = !url.nil?

      def branch_written? = branch_written
    end

    HOST = "github.com"
    SLUG = %r{\A[\w.-]+/[\w.-]+\z}
    # Marks commits Reanimator wrote, so a repeat run can tell its own branch
    # tip from a reviewer's.
    TRAILER = "Generated-by: reanimator"

    ELEVATED_NOTE = "**Elevated review.** This repository's contract includes verifier or " \
                    "contract-touching criteria, so this change needs a reviewer who can judge the " \
                    "rules of proof, not only the code."

    # @param client [#get, #post, #patch, nil] injected in specs; built from
    #   the token otherwise
    def initialize(client: nil, token: ENV[Configuration::GITHUB_TOKEN_ENV])
      @client = client || (GitHubClient.new(token: token) unless token.to_s.empty?)
      @branch_written = false
    end

    # @param proposal [Proposal]
    # @return [Outcome]
    def submit(proposal)
      @proposal = proposal
      @branch_written = false
      reason = obstacle
      return refused(reason) if reason

      point_branch(commit_patch)
      Outcome.new(publish, nil, true)
    rescue GitHubClient::Error => e
      refused(e.message)
    rescue KeyError, TypeError, NoMethodError => e
      refused("GitHub returned an unexpected response (#{e.message})")
    end

    private

    def precondition_failure
      return "no GitHub token; set #{Configuration::GITHUB_TOKEN_ENV}" unless @client
      return "Submission is not allowed: #{@proposal.blocker}" unless @proposal.submittable?
      return "the proposal's origin is on #{@proposal.host.inspect}, not #{HOST}" unless @proposal.host == HOST

      "#{@proposal.slug.inspect} is not an owner/name GitHub repository" unless SLUG.match?(@proposal.slug.to_s)
    end

    # The first reason this proposal must not be submitted, or nil. Checked in
    # order, so nothing is asked of GitHub once an earlier check refuses.
    def obstacle
      precondition_failure || moved_base_reason || ready_pull_reason || foreign_branch_reason
    end

    def repo = "/repos/#{@proposal.slug}"

    # Why the default branch no longer stands where the repair was verified,
    # or nil when its head is still the verified commit.
    def moved_base_reason
      @base = @client.get(repo).fetch("default_branch")
      @head = @client.get("#{repo}/git/ref/heads/#{GitHubClient.escape(@base)}").fetch("object").fetch("sha")
      return if @head == @proposal.base

      "#{@proposal.slug}@#{@base} is at #{@head.to_s[0, 12]}, not the verified #{@proposal.base[0, 12]}; " \
        "propose again from the current head"
    end

    # Why the open pull request must not receive commits, or nil.
    def ready_pull_reason
      owner = @proposal.slug.split("/").first
      @pull = @client.get("#{repo}/pulls?state=open&head=#{GitHubClient.escape("#{owner}:#{@proposal.branch}")}").first
      return if @pull.nil? || @pull.fetch("draft")

      "pull request #{@pull.fetch("html_url")} was marked ready for review; not adding unreviewed commits"
    end

    def branch_ref = "#{repo}/git/ref/heads/#{GitHubClient.escape(@proposal.branch)}"

    # Why the existing branch must not be moved, or nil when it is absent or
    # its tip is a commit Reanimator wrote.
    def foreign_branch_reason
      tip = @client.get(branch_ref).fetch("object").fetch("sha")
      message = @client.get("#{repo}/git/commits/#{tip}").fetch("message")
      @branch_exists = true
      return if message.include?(TRAILER)

      "#{@proposal.branch} has commits Reanimator did not write (tip #{tip[0, 12]}); not overwriting them"
    rescue GitHubClient::Error => e
      raise unless e.status == 404

      @branch_exists = false
      nil
    end

    # One commit on top of the verified head holding exactly the proposal.
    def commit_patch
      base_tree = @client.get("#{repo}/git/commits/#{@head}").fetch("tree").fetch("sha")
      tree = @client.post("#{repo}/git/trees", base_tree: base_tree, tree: entries).fetch("sha")
      @client.post("#{repo}/git/commits",
        message: "#{@proposal.title}\n\n#{TRAILER}", tree: tree, parents: [@head]).fetch("sha")
    end

    def entries
      @proposal.edits.map do |edit|
        entry = {path: edit.fetch(:path), mode: edit.fetch(:mode), type: "blob"}
        edit[:delete] ? entry.merge(sha: nil) : entry.merge(content: edit.fetch(:contents))
      end
    end

    def point_branch(commit)
      if @branch_exists
        @client.patch("#{repo}/git/refs/heads/#{GitHubClient.escape(@proposal.branch)}", sha: commit, force: true)
      else
        @client.post("#{repo}/git/refs", ref: "refs/heads/#{@proposal.branch}", sha: commit)
      end
      @branch_written = true
    end

    def publish
      title = @proposal.elevated_review ? "[elevated review] #{@proposal.title}" : @proposal.title
      body = @proposal.elevated_review ? "#{@proposal.body}\n\n#{ELEVATED_NOTE}" : @proposal.body
      if @pull
        @client.patch("#{repo}/pulls/#{@pull.fetch("number")}", title: title, body: body).fetch("html_url")
      else
        @client.post("#{repo}/pulls",
          title: title, body: body, head: @proposal.branch, base: @base, draft: true).fetch("html_url")
      end
    end

    def refused(reason) = Outcome.new(nil, reason, @branch_written)
  end
end
