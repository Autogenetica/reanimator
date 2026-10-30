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
    SCHEME_REMOTE = %r{\A([a-z][a-z0-9+.-]*)://(?:([^@/]+)@)?([^/:]+)(?::(\d+))?/(.+?)(?:\.git)?/?\z}i
    # [user@]host:path - scp-like; what follows the colon is always path, so
    # git@github.com:1234/widget names the owner 1234, not a port.
    SCP_REMOTE = %r{\A(?:([^@/]+)@)?([^/:]+):(?!//)(.+?)(?:\.git)?/?\z}
    DEFAULT_PORTS = {"ssh" => "22", "https" => "443", "http" => "80", "git" => "9418"}.freeze
    # Forges where a path is owner/repository, case-insensitive, and the user
    # is only transport (git@, a CI token). Elsewhere a path is a filesystem
    # path: case matters, an SSH user selects whose home it is relative to, and
    # an absolute path is not the same as a home-relative one.
    CASE_INSENSITIVE_FORGES = %w[github.com gitlab.com bitbucket.org].freeze
    # Schemes whose user part is a credential rather than part of the address.
    CREDENTIAL_USER_SCHEMES = %w[http https].freeze

    # A parsed remote. `path` keeps a leading "/" when it is absolute.
    Remote = Struct.new(:scheme, :user, :host, :port, :path)

    # Which repository a remote URL names, independent of how it is reached:
    # git@github.com:Org/repo.git and https://github.com/org/repo are the same
    # repository. Anything that could tell two repositories apart is kept - a
    # non-default port, path case and the SSH user off the known forges, an
    # absolute versus a home-relative path. File URLs, local paths and
    # unrecognised forms get their own "raw:" namespace and only match exactly.
    #
    # @param url [String, nil]
    # @return [String, nil] e.g. "github.com/org/repo"
    def remote_identity(url)
      return if url.nil?

      remote = parse_remote(url)
      return "raw:#{url.strip}" unless remote

      address = remote.port ? "#{remote.host}:#{remote.port}" : remote.host
      return "#{address}/#{remote.path.delete_prefix("/").downcase}" if CASE_INSENSITIVE_FORGES.include?(remote.host)

      user = remote.user unless CREDENTIAL_USER_SCHEMES.include?(remote.scheme)
      "#{"#{user}@" if user}#{address}:#{remote.path}"
    end

    # @return [Remote, nil]
    def parse_remote(url)
      url = url.to_s.strip
      if (scheme = SCHEME_REMOTE.match(url))
        return if scheme[1].casecmp?("file")

        name = scheme[1].downcase
        port = scheme[4] unless DEFAULT_PORTS[name] == scheme[4]
        Remote.new(name, scheme[2], scheme[3].downcase, port, "/#{scheme[5]}")
      elsif (scp = SCP_REMOTE.match(url))
        Remote.new("ssh", scp[1], scp[2].downcase, nil, scp[3])
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
