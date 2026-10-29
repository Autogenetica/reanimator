# frozen_string_literal: true

require "open3"
require "tmpdir"
require "fileutils"

module Reanimator
  # The committed tree at HEAD, exported into a throwaway directory so a repair
  # meant for submission is verified against exactly what a pull request would
  # be built on (specification section 11, submit rung). A working-tree copy
  # can carry ignored, untracked, assume-unchanged or skip-worktree files that
  # make checks pass locally and are absent from the commit; the export holds
  # only HEAD, so there is nothing for a cleanliness check to miss.
  #
  # It refuses anything but a repository root: patch paths are root-relative,
  # and a pull request is built from the top of the tree.
  class CommittedTree
    attr_reader :root, :path, :head

    # @param root [String] the checkout to export
    # @yieldparam tree [CommittedTree]
    # @raise [RepositoryError] when the path is not a repository root with a commit
    def self.export(root)
      root = File.realpath(File.expand_path(root.to_s))
      top = Git.capture(root, "rev-parse", "--show-toplevel")
      raise RepositoryError, "#{root} is not a git checkout; a proposal needs a commit to build on." unless top
      unless File.realpath(top) == root
        raise RepositoryError, "#{root} is inside #{top}; propose from the repository root, where pull-request paths are rooted."
      end

      head = Git.head_sha(root) or raise RepositoryError, "#{root} has no commit to propose against."
      destination = Dir.mktmpdir("reanimator-head")
      begin
        unpack(root, head, destination)
        yield new(root: root, path: destination, head: head)
      ensure
        FileUtils.remove_entry(destination, true)
      end
    end

    def self.unpack(root, head, destination)
      statuses = Open3.pipeline(%W[git -C #{root} archive --format=tar #{head}], %W[tar -x -C #{destination}],
        err: File::NULL)
      return if statuses.all?(&:success?)

      raise RepositoryError, "Could not export #{head[0, 12]} from #{root}."
    end
    private_class_method :unpack

    def initialize(root:, path:, head:)
      @root = root
      @path = path
      @head = head
    end

    # A repository whose files are HEAD and whose identity - name, origin,
    # history - is the real checkout's, so reports and proposals name it
    # correctly.
    #
    # @return [Repository]
    def repository
      declared = ContractFile.load(path)
      Repository.new(path: path, metadata: RepositoryMetadata.from_local(root), declared: declared,
        intent: declared&.intent)
    end

    # The committed mode of each path, as a pull request must preserve it.
    # Paths not in HEAD are new regular files.
    #
    # @param paths [Array<String>]
    # @return [Hash{String=>String}] path => git mode ("100644", "100755", "120000", ...)
    def modes(paths)
      paths.to_h do |relative|
        entry = Git.capture(root, "ls-tree", head, "--", relative)
        [relative, entry ? entry.split(" ", 2).first : "100644"]
      end
    end
  end
end
