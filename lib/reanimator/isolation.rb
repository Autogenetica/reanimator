# frozen_string_literal: true

require "tmpdir"
require "fileutils"

module Reanimator
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
    #
    # Symlinks are copied as links, and a link that leads out of the copy -
    # absolute, or relative past its root - is left out: a check must prove
    # the repository, not whatever a link points at, and an absolute link
    # would lead back into the original working tree.
    def copy(root)
      destination = Dir.mktmpdir("reanimator-iso")
      Dir.children(root).each do |child|
        next if child == ".git"

        FileUtils.cp_r(File.join(root, child), File.join(destination, child), dereference_root: false)
      end
      drop_links_out(destination)

      return destination unless block_given?

      begin
        yield destination
      ensure
        FileUtils.remove_entry(destination, true)
      end
    end

    # Removes every link in the copy that leads out of it: an absolute
    # target, a relative one that climbs past the root, or one whose real
    # path - through other links - lies outside. Every link is judged before
    # any is removed. A link inside the copy, even a dangling one, stays.
    def drop_links_out(destination)
      top = File.realpath(destination)
      links = Dir.glob("**/*", File::FNM_DOTMATCH, base: top).map { |relative| File.join(top, relative) }
        .select { |path| File.symlink?(path) }
      links.select { |link| leads_out?(link, top) }.each { |link| File.delete(link) }
    end

    def leads_out?(link, top)
      target = File.readlink(link)
      inside = ->(path) { path == top || path.start_with?("#{top}/") }
      # An absolute target expands to itself, so it is judged here too.
      return true unless inside.call(File.expand_path(target, File.dirname(link)))

      !inside.call(File.realpath(link))
    rescue SystemCallError
      false # dangling inside the copy: nothing outside to reach
    end
  end
end
