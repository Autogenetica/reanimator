# frozen_string_literal: true

require "tmpdir"
require "fileutils"

module Frankenstein
  # Disposable-workspace helper (specification section 12: "disposable
  # workspaces", section 14: "all commands run in a disposable workspace"). It
  # copies a repository into a throwaway directory so an agent can work, and so
  # evaluation can run, without ever touching the original source. The agent's
  # workspace and the evaluation workspace are always distinct copies - verifier
  # isolation by construction.
  module Isolation
    module_function

    # Copies a repository root into a fresh temp directory (excluding .git),
    # yielding the copy to the block and removing it afterward. Without a block
    # it returns the path and the caller owns cleanup.
    def copy(root)
      destination = Dir.mktmpdir("frankenstein-iso")
      Dir.children(root).each do |child|
        next if child == ".git"

        FileUtils.cp_r(File.join(root, child), File.join(destination, child))
      end

      return destination unless block_given?

      begin
        yield destination
      ensure
        FileUtils.remove_entry(destination, true)
      end
    end
  end
end
