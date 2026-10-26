# frozen_string_literal: true

require "fileutils"

module Reanimator
  # Where a repository's recorded contract snapshot lives - and the only place
  # Reanimator ever writes one (specification section 06).
  #
  # There are two conventions, because drift has two shapes. A repository you
  # own records its snapshot *inside itself*, as a committed file beside
  # `.reanimator.yml`: the contract and the record of what it last required
  # are the same kind of thing, and keeping both under review means a policy
  # change arrives as a diff a human reads rather than as state hidden in a
  # tool. A portfolio of repositories you cannot write into records them side
  # by side in one directory instead, keyed by repository.
  class SnapshotStore
    DEFAULT_FILENAME = ".reanimator-snapshot.json"

    # @return [String, nil] the portfolio-side directory, or nil when each
    #   repository keeps its own committed snapshot
    attr_reader :directory

    def initialize(directory: nil)
      @directory = directory
    end

    # @param repository [Repository]
    # @return [String] where this repository's snapshot is read from and written to
    def path_for(repository)
      return File.join(repository.path, DEFAULT_FILENAME) unless directory

      File.join(directory, "#{key_for(repository)}.json")
    end

    def recorded?(repository) = File.file?(path_for(repository))

    # @param repository [Repository]
    # @return [ContractSnapshot, nil] nil when nothing has been recorded yet
    def load(repository)
      recorded?(repository) ? ContractSnapshot.load(path_for(repository)) : nil
    end

    # @param snapshot [ContractSnapshot]
    # @param repository [Repository]
    # @return [String] the path written
    def save(snapshot, repository)
      destination = path_for(repository)
      FileUtils.mkdir_p(directory) if directory
      File.write(destination, snapshot.to_json)
      destination
    rescue SystemCallError => e
      raise ContractError, "Could not write the contract snapshot to #{destination}: #{e.message}"
    end

    # The exact command a maintainer runs to re-record a snapshot, for a report
    # to quote. The store is the one place that knows where snapshots live, so
    # it is also the one place that knows how to say "put it back".
    #
    # @param file [String, nil] an explicitly named snapshot file, if the
    #   maintainer bypassed the store with one
    def record_command(file = nil)
      return "reanimator drift --save #{file}" if file
      return "reanimator drift --record --snapshots #{directory}" if directory

      "reanimator drift --record"
    end

    private

    # A repository's identity flattened into one filename. A collision is not a
    # correctness risk: {DriftDetector} refuses to compare snapshots from two
    # different repositories, so a mis-keyed file fails closed instead of
    # reporting the most dangerous possible answer - "no drift".
    def key_for(repository)
      repository.full_name.to_s.gsub(/[^A-Za-z0-9._-]+/, "-")
    end
  end
end
