# frozen_string_literal: true

require "open3"

module Reanimator
  # A deliberately tiny, read-only wrapper around the git CLI. Reanimator
  # never mutates a repository during observation or discovery, so this helper
  # only ever runs inspection commands and returns nil rather than raising when
  # git is absent or the command fails - a repository without git history is a
  # fact to record, not a crash.
  module Git
    module_function

    # @param root [String] repository working directory
    # @return [Boolean] whether the path is inside a git working tree
    def repository?(root)
      capture(root, "rev-parse", "--is-inside-work-tree") == "true"
    end

    # @return [String, nil] the origin remote URL, if any
    def origin_url(root)
      capture(root, "config", "--get", "remote.origin.url")
    end

    # Forges whose repositories are named owner/repo (GitLab adds subgroups),
    # case-insensitively, with or without .git, and where the user part is only
    # transport (git@, a CI token). Only these are normalised.
    FORGES = %w[github.com gitlab.com bitbucket.org].freeze
    FORGE_HOST = FORGES.map { |host| Regexp.escape(host) }.join("|")
    # A forge remote, parsed only the way git itself reads it:
    # scheme://[user[:secret]@]host[:port]/owner/repo or [user@]host:owner/repo.
    # An scp-like user cannot contain ":" - git splits the host at the first
    # colon - so evil.example:x@github.com:org/repo is not a GitHub remote.
    FORGE_REMOTE = %r{\A(?:(?:ssh|git|https?)://(?:[^@/:]+(?::[^@/]*)?@)?(#{FORGE_HOST})(?::\d+)?/|
                       (?:[^@/:]+@)?(#{FORGE_HOST}):)([\w.-]+(?:/[\w.-]+)+)/?\z}xi
    # Prefix for remotes compared exactly; forge identities never contain "=".
    EXACT = "="

    # Which repository a remote URL names. On the known forges, every way of
    # reaching one repository - SSH or HTTPS, any user or token, any case, with
    # or without .git - has one identity. Every other remote is compared
    # exactly, apart from surrounding whitespace and a trailing slash: off the
    # forges, users, ports, case, .git and absolute versus home-relative paths
    # can each name a different repository, and guessing wrong would report
    # "no drift" against another repository's snapshot. The cost is that a
    # self-hosted forge checked over a different transport is refused - the
    # safe direction.
    #
    # @param url [String, nil]
    # @return [String, nil] e.g. "github.com/org/repo", or "=git@host:/srv/repo"
    def remote_identity(url)
      return if url.nil?

      text = url.strip
      forge = FORGE_REMOTE.match(text)
      return "#{EXACT}#{text.chomp("/")}" unless forge

      "#{(forge[1] || forge[2]).downcase}/#{forge[3].delete_suffix(".git").downcase}"
    end

    # @return [Boolean] whether an "upstream" remote is configured, a strong
    #   local hint that the repository is a maintained fork
    def upstream_remote?(root)
      !capture(root, "config", "--get", "remote.upstream.url").nil?
    end

    # @return [String, nil] the current branch name
    def current_branch(root)
      branch = capture(root, "rev-parse", "--abbrev-ref", "HEAD")
      branch unless branch == "HEAD"
    end

    # @return [Time, nil] author time of the most recent commit
    def last_commit_at(root)
      iso = capture(root, "log", "-1", "--format=%cI")
      Time.parse(iso) if iso && !iso.empty?
    rescue ArgumentError
      nil
    end

    # @return [Integer, nil] number of commits, a cheap activity signal
    def commit_count(root)
      count = capture(root, "rev-list", "--count", "HEAD")
      Integer(count) if count
    rescue ArgumentError
      nil
    end

    # @return [Array<String>] tracked files (fast, respects .gitignore); empty
    #   when git is unavailable
    def tracked_files(root)
      out = capture(root, "ls-files")
      out ? out.split("\n") : []
    end

    # Runs a read-only git command, returning trimmed stdout or nil on any
    # failure. stderr is discarded - callers treat "no answer" as the signal.
    def capture(root, *args)
      require "time"
      stdout, _stderr, status = Open3.capture3("git", "-C", root.to_s, *args)
      return nil unless status.success?
      value = stdout.strip
      value.empty? ? nil : value
    rescue Errno::ENOENT
      nil
    end
  end
end
