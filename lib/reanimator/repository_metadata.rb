# frozen_string_literal: true

module Reanimator
  # The read-only facts about a repository that exist before any detector runs
  # (specification section 04 inventory inputs): name, ownership, default
  # branch, primary language, fork status, and last activity. This object is
  # the seam between "where the repository lives" and "what it is": a local
  # working tree fills it from git today, and a GitHub inventory source can
  # fill the very same shape tomorrow without touching the rest of the system.
  class RepositoryMetadata
    attr_reader :name, :full_name, :default_branch, :primary_language,
      :last_activity, :commit_count, :topics

    def initialize(name:, full_name: nil, default_branch: nil, primary_language: nil,
      fork: false, archived: false, last_activity: nil, commit_count: nil, topics: [], has_git: false)
      @name = name
      @full_name = full_name
      @default_branch = default_branch
      @primary_language = primary_language
      @fork = fork
      @archived = archived
      @last_activity = last_activity
      @commit_count = commit_count
      @topics = topics
      @has_git = has_git
    end

    def fork? = @fork

    def archived? = @archived

    def has_git? = @has_git

    # Days since the last commit, or nil when unknown. Feeds the "old
    # unarchived repository" and "recent experiment" cohort heuristics.
    def days_since_activity(now: Time.now)
      return nil unless last_activity
      ((now - last_activity) / 86_400).floor
    end

    # Builds metadata from a local working tree. Everything is best-effort:
    # a directory that is not a git repository still yields a usable object.
    def self.from_local(root)
      has_git = Git.repository?(root)
      origin = has_git ? Git.origin_url(root) : nil
      new(
        name: File.basename(root),
        full_name: full_name_from_url(origin),
        default_branch: has_git ? Git.current_branch(root) : nil,
        primary_language: LanguageInference.call(root),
        fork: has_git && Git.upstream_remote?(root),
        archived: false,
        last_activity: has_git ? Git.last_commit_at(root) : nil,
        commit_count: has_git ? Git.commit_count(root) : nil,
        topics: [],
        has_git: has_git
      )
    end

    # Parses "owner/repo" from a git remote URL in either SSH or HTTPS form.
    def self.full_name_from_url(url)
      return nil unless url
      cleaned = url.sub(/\.git\z/, "")
      case cleaned
      when %r{[:/]([^/:]+)/([^/]+)\z}
        "#{$1}/#{$2}"
      end
    end

    def to_h
      {
        name: name, full_name: full_name, default_branch: default_branch,
        primary_language: primary_language, fork: fork?, archived: archived?,
        last_activity: last_activity&.iso8601, commit_count: commit_count, topics: topics
      }
    end
  end
end
