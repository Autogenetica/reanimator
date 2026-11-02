# frozen_string_literal: true

module Reanimator
  # A single repository under (potential) stewardship: its location, its
  # read-only metadata, any owner-declared contract, and the lifecycle intent
  # currently assigned to it. Detectors read a repository through the file
  # helpers here so they never reach outside its root, and so a future
  # non-filesystem source could satisfy the same surface.
  class Repository
    # @return [String] absolute path to the working tree
    attr_reader :path
    # @return [RepositoryMetadata]
    attr_reader :metadata
    # @return [ContractFile, nil] parsed .reanimator.yml, when present
    attr_reader :declared
    # @return [Symbol, nil] assigned lifecycle intent (mutable during onboarding)
    attr_accessor :intent

    # Builds a repository from a path on disk.
    # @raise [RepositoryError] when the path is not a directory
    def self.at(path)
      root = File.expand_path(path.to_s)
      unless File.directory?(root)
        raise RepositoryError, "#{path.inspect} is not a directory."
      end

      declared = ContractFile.load(root)
      new(
        path: root,
        metadata: RepositoryMetadata.from_local(root),
        declared: declared,
        intent: declared&.intent
      )
    end

    def initialize(path:, metadata:, declared: nil, intent: nil)
      @path = path
      @metadata = metadata
      @declared = declared
      @intent = intent
    end

    def name = metadata.name

    def full_name = metadata.full_name || metadata.name

    def fork? = metadata.fork?

    # Whether the owner committed a contract file. When true, the declared
    # profile and intent win over inference (section 06 conflict resolution).
    def declared? = !declared.nil?

    # @return [Symbol, nil] the profile the owner declared, if any
    def declared_profile = declared&.profile

    # --- read-only file access used by detectors -----------------------------

    # @return [String] absolute path for a repository-relative path
    def absolute(relative) = File.join(path, relative)

    # @return [Boolean] whether a repository-relative path exists
    def exist?(relative) = File.exist?(absolute(relative))

    # @return [Array<String>] repository-relative paths matching a glob.
    #   Globbed from the root rather than trimmed from absolute paths: on a
    #   case-insensitive filesystem the matches come back in their real case,
    #   which a root given in another case would not trim.
    #   Evidence comes from the repository or not at all, so a match is kept
    #   only when its real path lies inside the root's: glob syntax is too
    #   rich to judge by the pattern - braces, escapes and a symlink can each
    #   lead out - so the matches themselves are judged.
    def glob(pattern)
      Dir.glob(pattern, File::FNM_DOTMATCH, base: path).select { |match| inside?(match) }.sort
    rescue ArgumentError # a pattern Ruby refuses, such as one with a NUL byte
      []
    end

    # A match written inside the root - neither absolute nor through `..` -
    # whose real path is inside it too.
    def inside?(match)
      return false if match.start_with?("/") || match.split("/").include?("..")

      real = File.realpath(match, path)
      real == real_root || real.start_with?("#{real_root}/")
    rescue SystemCallError
      false
    end
    private :inside?

    def real_root = @real_root ||= File.realpath(path)
    private :real_root

    # @return [Boolean] whether any path matches the glob
    def any?(pattern) = !glob(pattern).empty?

    # @return [String, nil] contents of a repository-relative file, or nil.
    #   Repository content is untrusted and may not be valid UTF-8; it is read
    #   as UTF-8 and scrubbed so a detector's regex or slice can never raise on
    #   a stray byte (which would otherwise be swallowed as a "detector failed"
    #   and silently drop facts), including under a C/US-ASCII locale.
    # A directory where a file is expected is not that file, so it reads as
    # absent; a file Reanimator can see but not read still raises. A file
    # behind a directory it cannot search is not seen at all, and reads as
    # absent - as File.exist? did before.
    def read(relative)
      return unless File.file?(absolute(relative))

      File.read(absolute(relative), encoding: "UTF-8").scrub
    end

    def to_h
      {
        name: name,
        full_name: full_name,
        path: path,
        intent: intent,
        declared: declared?,
        metadata: metadata.to_h
      }
    end
  end
end
