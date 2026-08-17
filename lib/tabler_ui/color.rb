# frozen_string_literal: true

module TablerUi
  # Shared colour vocabulary and validation for components that accept a
  # `color:` option (badge, status, buttons, etc).
  module Color
    TABLER = %w[
      blue azure indigo purple pink red orange yellow lime green teal cyan
    ].freeze

    SEMANTIC = %w[
      primary secondary success danger warning info light dark
    ].freeze

    ALL = (TABLER + SEMANTIC).freeze

    # Brand colours. Tabler defines .btn-<brand>, .btn-outline-<brand> and
    # .btn-ghost-<brand> for these, but no bg-/text- utilities, so they are only
    # valid on buttons -- passed in via validate!'s `extra:`.
    BRAND = %w[x facebook twitter linkedin google youtube vimeo dribbble
               github instagram pinterest vk rss flickr bitbucket tabler].freeze

    # Not part of the general palette: only .alert-muted and .btn-muted exist.
    MUTED = %w[muted].freeze

    module_function

    def valid?(value, extra: [])
      return false if value.nil?

      (ALL + extra).include?(value.to_s)
    end

    # Returns the colour as a String, or raises ArgumentError naming the
    # offender and listing the valid values. Passing nil returns nil (colour
    # is optional). `extra:` widens the accepted values for this call site
    # only (e.g. BRAND on buttons) without widening ALL for everyone else.
    def validate!(value, extra: [], context: nil)
      return nil if value.nil?

      value = value.to_s
      accepted = ALL + extra
      return value if accepted.include?(value)

      where = context ? " for #{context}" : ""
      raise ArgumentError, "unknown color #{value.inspect}#{where} — valid: #{accepted.join(', ')}"
    end
  end
end
