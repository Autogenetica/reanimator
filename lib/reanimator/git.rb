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

    # scheme://[user@]host[:port]/path - the only remote form with a port.
    SCHEME_REMOTE = %r{\A([a-z][a-z0-9+.-]*)://(?:[^@/]+@)?([^/:]+)(?::(\d+))?/(.+?)(?:\.git)?/?\z}i
    # [user@]host:path - scp-like; what follows the colon is always path, so
    # git@github.com:1234/widget names the owner 1234, not a port.
    SCP_REMOTE = %r{\A(?:[^@/]+@)?([^/:]+):(?!//)(.+?)(?:\.git)?/?\z}
    DEFAULT_PORTS = {"ssh" => "22", "https" => "443", "http" => "80", "git" => "9418"}.freeze

    # Splits a remote URL into the host, any non-default port, and the path.
    # File URLs, local paths and unrecognised forms have no host and return nil.
    #
    # @param url [String, nil]
    # @return [Array(String, String, String), nil] host (lowercased), port or nil, path
    def remote_parts(url)
      url = url.to_s.strip
      if (scheme = SCHEME_REMOTE.match(url))
        return if scheme[1].casecmp?("file")

        port = scheme[3] unless DEFAULT_PORTS[scheme[1].downcase] == scheme[3]
        [scheme[2].downcase, port, scheme[4]]
      elsif (scp = SCP_REMOTE.match(url))
        [scp[1].downcase, nil, scp[2]]
      end
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

    # @return [String, nil] the commit HEAD points at
    def head_sha(root)
      capture(root, "rev-parse", "HEAD")
    end

    # Whether the working tree has no uncommitted or untracked changes. A
    # failed git call is not "clean": callers use this to decide whether what
    # they verified is what is committed, so they must not be told yes by
    # default.
    #
    # @return [Boolean]
    def clean?(root)
      stdout, _stderr, status = Open3.capture3("git", "-C", root.to_s, "status", "--porcelain")
      status.success? && stdout.strip.empty?
    rescue Errno::ENOENT
      false
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
