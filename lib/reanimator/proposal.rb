# frozen_string_literal: true

require "json"

module Reanimator
  # A verified repair, written down so a separate process can submit it
  # (specification section 11, submit rung). Submission is split in two on
  # purpose: the process that runs repository code never holds the GitHub
  # token, and the process that holds the token runs no repository code - it
  # reads this file and talks to the GitHub API, nothing else.
  #
  # A proposal records what was verified (the base commit and the exact file
  # contents and modes) and what the contract allowed when it was made, so the
  # submitter can refuse anything the repair did not prove or the owner did
  # not permit.
  class Proposal
    FORMAT = 1
    # Git modes a pull request may write. Symlinks (120000) and submodules
    # (160000) are refused: a patch written through either is not the file
    # that was verified.
    WRITABLE_MODES = %w[100644 100755].freeze

    attr_reader :host, :slug, :base, :branch, :title, :body, :edits, :elevated_review, :blocker

    # @param edits [Array<Hash>] {path:, mode:, contents:} or {path:, mode:, delete: true}
    # @param blocker [String, nil] why the contract does not allow submission
    def initialize(host:, slug:, base:, branch:, title:, body:, edits:, elevated_review:, blocker: nil)
      @host = host
      @slug = slug
      @base = base
      @branch = branch
      @title = title
      @body = body
      @edits = edits
      @elevated_review = elevated_review
      @blocker = blocker
      freeze
    end

    # @param change [ProposedChange] the verified repair
    # @param tree [CommittedTree] the commit it was verified against
    # @param contract [EffectiveContract]
    # @param task_class [Symbol]
    # @raise [PolicyViolation] when a patched path is a symlink or submodule
    def self.build(change, tree:, contract:, task_class:)
      modes = tree.modes(change.patch.paths)
      unwritable = modes.reject { |_, mode| WRITABLE_MODES.include?(mode) }.keys
      unless unwritable.empty?
        raise PolicyViolation, "Refusing to propose a change to a symlink or submodule: #{unwritable.join(", ")}."
      end

      resolution = PermissionModel.new(contract).resolve(task_class)
      host, slug = remote(tree.root)
      new(
        host: host, slug: slug, base: tree.head, branch: change.branch, title: change.title, body: change.body,
        edits: change.patch.edits.map { |edit| record(edit, modes.fetch(edit.path)) },
        elevated_review: resolution.elevated_review?, blocker: blocker_for(resolution, task_class)
      )
    end

    def self.record(edit, mode)
      edit.delete? ? {path: edit.path, mode: mode, delete: true} : {path: edit.path, mode: mode, contents: edit.contents}
    end

    def self.blocker_for(resolution, task_class)
      return if resolution.opens_pull_requests?
      return "the #{task_class} task class may only open an issue, not a pull request" if resolution.submit_policy == :issue

      "the contract does not enable it (set autonomy: submit: allowed in #{Reanimator.configuration.contract_filename})"
    end

    # The host (with any non-default port) and owner/name the checkout's
    # origin names, or nil for each.
    def self.remote(root)
      host, port, path = Git.remote_parts(Git.origin_url(root))
      return [nil, nil] unless host

      [port ? "#{host}:#{port}" : host, path.delete_prefix("/")]
    end
    private_class_method :record, :blocker_for, :remote

    # @param path [String]
    # @raise [ContractError] when the file is missing or not a proposal
    def self.load(path)
      data = JSON.parse(File.read(path), symbolize_names: true)
      unless data[:format] == FORMAT
        raise ContractError, "#{path} is not a Reanimator proposal (format #{data[:format].inspect})."
      end

      new(**data.slice(:host, :slug, :base, :branch, :title, :body, :elevated_review, :blocker),
        edits: data.fetch(:edits))
    rescue Errno::ENOENT, JSON::ParserError, KeyError, ArgumentError => e
      raise ContractError, "Could not read proposal #{path}: #{e.message}"
    end

    def submittable? = blocker.nil?

    def paths = edits.map { |edit| edit[:path] }

    def to_h
      {format: FORMAT, host: host, slug: slug, base: base, branch: branch, title: title, body: body,
       elevated_review: elevated_review, blocker: blocker, edits: edits}
    end

    # @param path [String]
    def write(path)
      File.write(path, JSON.pretty_generate(to_h))
      path
    end
  end
end
