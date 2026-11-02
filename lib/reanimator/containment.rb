# frozen_string_literal: true

module Reanimator
  # Whether a file Reanimator reads or writes on a repository's behalf really
  # lies inside it. A committed symlink can point anywhere, and a contract,
  # snapshot or piece of evidence that lives elsewhere is not the
  # repository's own.
  module Containment
    module_function

    # @param root [String] the repository root
    # @param path [String] an absolute path under the root, as written
    # @return [Boolean] whether its real path lies inside the root's
    def inside?(root, path)
      real_root = File.realpath(root)
      real = File.realpath(path)
      real == real_root || real.start_with?("#{real_root}/")
    rescue SystemCallError
      false
    end

    # Raises unless a path that exists - as a file or as a link - is inside
    # the root; a path that does not exist at all passes.
    def ensure_inside!(root, path, what)
      return unless File.symlink?(path) || File.exist?(path)
      return if inside?(root, path)

      raise ContractError, "#{what} links outside the repository, so it is not this repository's own."
    end
  end
end
