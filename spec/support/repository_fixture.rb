# frozen_string_literal: true

# Builds throwaway repositories on disk for detector, resolver, and baseline
# specs. A fixture is a plain directory of files, optionally turned into a real
# git repository (with a commit, or an upstream remote) so metadata-driven code
# paths - fork detection, integrity, activity - can be exercised for real
# rather than stubbed.
module RepositoryFixture
  # @param files [Hash{String=>String}] repository-relative path => contents
  # @param git [Boolean] initialize a git repo and make one commit
  # @param upstream [String, nil] add an "upstream" remote with this URL
  # @return [String] absolute path to the fixture
  def make_repo(files: {}, git: false, upstream: nil)
    dir = Dir.mktmpdir("frankenstein-spec")
    (@fixture_dirs ||= []) << dir

    files.each do |relative, contents|
      full = File.join(dir, relative)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, contents)
    end

    init_git(dir, upstream: upstream) if git || upstream
    dir
  end

  # Builds a fixture and returns a loaded {Frankenstein::Repository}.
  def make_repository(**kwargs)
    Frankenstein::Repository.at(make_repo(**kwargs))
  end

  private

  def init_git(dir, upstream: nil)
    git(dir, "init", "-q", "-b", "main")
    File.write(File.join(dir, ".gitkeep"), "") unless Dir.children(dir).any? { |c| c != ".git" }
    git(dir, "add", "-A")
    git(dir, "-c", "user.email=test@example.com", "-c", "user.name=Test",
      "commit", "-q", "-m", "fixture")
    git(dir, "remote", "add", "upstream", upstream) if upstream
  end

  def git(dir, *args)
    system("git", "-C", dir, *args, out: File::NULL, err: File::NULL) ||
      raise("git #{args.join(" ")} failed in #{dir}")
  end
end
