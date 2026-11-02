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
      begin
        Dir.children(root).each do |child|
          next if child == ".git"

          FileUtils.cp_r(File.join(root, child), File.join(destination, child), dereference_root: false)
        end
        report_dropped(drop_links_out(destination))
      rescue Exception # standard:disable Lint/RescueException - nothing may leave the copy behind
        FileUtils.remove_entry(destination, true)
        raise
      end

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
    # @return [Array<String>] the copy-relative paths of the links removed
    def drop_links_out(destination)
      top = File.realpath(destination)
      links = Dir.glob("**/*", File::FNM_DOTMATCH, base: top).select { |relative| File.symlink?(File.join(top, relative)) }
      links.select { |relative| leads_out?(File.join(top, relative), top) }
        .each { |relative| File.delete(File.join(top, relative)) }
    end

    # Judged as written first - with File.absolute_path, which keeps a ~ as
    # the name it is - so a dangling link out, which has no real path yet, is
    # caught; then by its real path, for a link that leads out through
    # another. A target that cannot be judged leads out.
    def leads_out?(link, top)
      inside = ->(path) { path == top || path.start_with?("#{top}/") }
      return true unless inside.call(File.absolute_path(File.readlink(link), File.dirname(link)))

      !inside.call(File.realpath(link))
    rescue Errno::ENOENT, Errno::ELOOP
      false # dangling, or a loop, inside the copy: nothing outside to reach
    rescue SystemCallError, ArgumentError, EncodingError
      true
    end

    # A link left out changes what a check sees, so the run says so.
    def report_dropped(dropped)
      return if dropped.empty?

      Reanimator.logger.warn(
        "Left #{dropped.size} link(s) out of the disposable copy because they lead outside the repository: #{dropped.join(", ")}"
      )
    end
  end
end
