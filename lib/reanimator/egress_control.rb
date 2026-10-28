# frozen_string_literal: true

module Reanimator
  # Decides how executed checks are held to the security posture's network
  # promise (specification section 12). A posture that denies egress is either
  # *enforced* - every command runs inside an empty network namespace - or the
  # run *refuses* to execute. It never runs unprotected while the posture says
  # otherwise: the same fail-closed rule applied to unreadable snapshots and
  # expired waivers.
  #
  # Enforcement uses an unprivileged Linux user + network namespace
  # (`unshare`), which leaves the command only a loopback interface. There is
  # deliberately no macOS path: `sandbox-exec` is deprecated, so elsewhere a
  # denying posture refuses rather than pretending.
  #
  # Postures that permit network are not restricted, and the decision says so
  # plainly - the balanced posture's package-registry allowlist is advisory.
  module EgressControl
    # How one run treats the network.
    #
    # mode   - :denied (enforced), :unrestricted, or :refused
    # prefix - argv placed before the command (nil when refused)
    # reason - plain-language statement of what is, or is not, enforced
    Decision = Struct.new(:mode, :prefix, :reason) do
      def denied? = mode == :denied

      def refused? = mode == :refused
    end

    # Unprivileged namespace invocations, most faithful first.
    # `--map-current-user` keeps the caller's uid inside the namespace; older
    # util-linux only offers `--map-root-user`, which still isolates the network.
    NAMESPACE_PREFIXES = [
      %w[unshare --user --map-current-user --net],
      %w[unshare --user --map-root-user --net]
    ].freeze

    # Passes only when the namespace really is empty: the sole interface listed
    # in the process's own /proc/net/dev is loopback.
    LOOPBACK_ONLY = %q(test "$(sed -n '3,$p' /proc/net/dev | cut -d: -f1 | tr -d ' ')" = lo)

    module_function

    # @param posture [SecurityPosture]
    # @param namespace [#call] returns an enforcing argv prefix, or nil
    # @return [Decision]
    def for(posture, namespace: method(:namespace_prefix))
      case posture.network
      when :deny
        prefix = namespace.call
        if prefix
          Decision.new(mode: :denied, prefix: prefix, reason: "network egress denied by an empty network namespace")
        else
          Decision.new(mode: :refused, prefix: nil, reason: refusal(posture))
        end
      when :package_registries
        unrestricted("network not restricted; the #{posture} posture's package-registry allowlist is advisory")
      else
        unrestricted("network not restricted; the #{posture} posture declares no egress rule")
      end
    end

    # An argv prefix proven to isolate the network on this host, or nil. Probed
    # once per process: namespace support does not change while running.
    def namespace_prefix
      return @namespace_prefix if defined?(@namespace_prefix)

      @namespace_prefix = linux? ? NAMESPACE_PREFIXES.find { |prefix| isolates?(prefix) } : nil
    end

    def isolates?(prefix)
      system(*prefix, "sh", "-c", LOOPBACK_ONLY, out: File::NULL, err: File::NULL) == true
    rescue SystemCallError
      false
    end

    def linux? = RUBY_PLATFORM.include?("linux")

    def unrestricted(reason) = Decision.new(mode: :unrestricted, prefix: [], reason: reason)

    def refusal(posture)
      why = linux? ? "unprivileged network namespaces are unavailable" : "no network sandbox on #{RUBY_PLATFORM}"
      "the #{posture} posture requires denied network egress and this runner cannot enforce it (#{why})"
    end
  end
end
