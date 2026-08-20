# frozen_string_literal: true

module TablerUi
  # Shared front half of the `frame:` option accepted by `table` and
  # `pagination` -- a String shorthand for `{ id: the String }`, or a Hash
  # requiring at least `id:`.
  #
  # The two components deliberately diverge past that point, and this module
  # does not paper over it:
  #
  # * `table` also recognises `advance:`/`src:`/`loading:` on the Hash and
  #   validates `loading:` itself -- see Table::Component#build_frame.
  # * `pagination` silently ignores those same keys if present, and keeps
  #   only the normalized `id:` -- see the "Turbo Frames" section of
  #   Pagination::Component's class docs for why that's deliberate (a
  #   caller may pass the very same `frame:` hash it gave `table` straight
  #   through to `pagination`).
  #
  # This module owns only what both share: shorthand expansion, the
  # mandatory-id check (one error-message style, naming the component via
  # `context:`), and stringifying the id. It never decides what a caller
  # does with any other keys on the Hash -- that stays with the caller.
  module Frame
    module_function

    # @param value [String, Hash, nil] the raw frame: option
    # @param context [String] the component name, used in the error message
    # @return [Hash, nil] +value+ normalized to a Hash with a String :id, or
    #   nil when +value+ is nil (frame: is optional in both components).
    #   Any other keys on a Hash +value+ pass through untouched.
    # @raise [ArgumentError] when :id is missing or blank
    def normalize(value, context:)
      return nil if value.nil?

      hash = value.is_a?(String) ? { id: value } : value
      id = hash[:id]

      raise ArgumentError, "#{context} frame: is missing id: -- #{value.inspect}" if id.blank?

      hash.merge(id: id.to_s)
    end
  end
end
