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
        report_dropped(drop_links_out(destination) + drop_git_files(destination))
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
    # path - through other links - lies outside, or cannot be found. Every
    # link is judged before any is removed. A link to a missing file inside
    # the copy stays.
    # @return [Array<String>] the copy-relative paths of the links removed
    def drop_links_out(destination)
      top = File.realpath(destination)
      links = Dir.glob("**/*", File::FNM_DOTMATCH, base: top).select { |relative| File.symlink?(File.join(top, relative)) }
      links.select { |relative| leads_out?(File.join(top, relative), top) }
        .each { |relative| File.delete(File.join(top, relative)) }
    end

    # Judged as written first - with File.absolute_path, which keeps a ~ as
    # the name it is - then by its real path through every other link, which
    # File.realdirpath finds even when the final file does not exist yet: a
    # link can look inside as written (l/l/../../x with l -> .) and still
    # climb out. A link whose path cannot be resolved at all - a loop, a
    # missing directory, a file used as one - leads out, since nothing shows
    # where a write through it would land.
    def leads_out?(link, top)
      inside = ->(path) { path == top || path.start_with?("#{top}/") }
      target = File.readlink(link)
      return true unless inside.call(File.absolute_path(target, File.dirname(link)))
      return true if climbs_through_link?(target, File.dirname(link))

      !inside.call(File.realdirpath(link))
    rescue SystemCallError, ArgumentError, EncodingError
      true
    end

    # Removes every nested .git file - a worktree's or a submodule's pointer,
    # `gitdir: <path>` - from the copy. The top-level .git is never copied,
    # so each points either back into the original repository, where a git
    # command run by a check would commit, or nowhere.
    # @return [Array<String>] the copy-relative paths removed
    def drop_git_files(destination)
      Dir.glob("**/.git", File::FNM_DOTMATCH, base: destination)
        .select { |relative| File.file?(File.join(destination, relative)) && !File.symlink?(File.join(destination, relative)) }
        .each { |relative| File.delete(File.join(destination, relative)) }
    end

    # Whether the target, as written, climbs with `..` after passing through
    # a link. Where it lands then depends on what that link is, and a check
    # that replaces the link with a plain directory - an ordinary "reset
    # tmp/" step - would make a target judged inside climb out. Without such
    # a climb, plain directories cannot change where the path lands.
    def climbs_through_link?(target, from)
      through_link = false
      target.split("/").reject(&:empty?).inject(from) do |path, part|
        return true if part == ".." && through_link

        File.join(path, part).tap { |next_path| through_link ||= File.symlink?(next_path) }
      end
      false
    end

    # A link left out changes what a check sees, so the run says so.
    def report_dropped(dropped)
      return if dropped.empty?

      Reanimator.logger.warn(
        "Left #{dropped.size} path(s) out of the disposable copy because they lead outside the repository " \
        "or cannot be placed: #{dropped.join(", ")}"
      )
    end
  end
end
