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
    dir = Dir.mktmpdir("reanimator-spec")
    (@fixture_dirs ||= []) << dir

    files.each do |relative, contents|
      full = File.join(dir, relative)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, contents)
    end

    init_git(dir, upstream: upstream) if git || upstream
    dir
  end

  # Builds a fixture and returns a loaded {Reanimator::Repository}.
  def make_repository(**kwargs)
    Reanimator::Repository.at(make_repo(**kwargs))
  end

  # Creates a directory of *named* repositories under one parent, returning
  # their paths in the order given. Family inference keys off repository
  # names, so those names have to be controllable.
  #
  # @param repositories [Hash{String=>Hash}] name => (relative path => contents)
  # @return [Array<String>] absolute paths
  def make_portfolio(repositories)
    root = Dir.mktmpdir("reanimator-portfolio")
    (@fixture_dirs ||= []) << root

    repositories.map do |name, files|
      dir = File.join(root, name.to_s)
      FileUtils.mkdir_p(dir)
      (files || {}).each do |relative, contents|
        full = File.join(dir, relative)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, contents)
      end
      dir
    end
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
