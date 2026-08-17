# frozen_string_literal: true

module TablerUi
  # Shared edge vocabulary for components anchored to a side of something --
  # offcanvas panels, ribbons.
  #
  # TablerUi::Align covers the horizontal pair (:start/:end) used by dropdown
  # menus. This is the wider set, including the vertical edges, so callers of
  # both stay in one vocabulary rather than mixing "left"/"top"/"end".
  #
  # Like Color and Align, an unrecognised value raises rather than falling back:
  # a silently ignored position: "left" is a visual regression with nothing
  # pointing at the cause.
  module Position
    EDGES = %i[start end top bottom].freeze
    VERTICAL = %i[top bottom].freeze

    module_function

    def valid?(value, allowed: EDGES)
      return true if value.nil?

      allowed.include?(value.to_s.to_sym)
    end

    # Returns the position as a Symbol, or nil when none was given (position is
    # optional; each component supplies its own default). +allowed+ narrows the
    # set for components that only accept part of it -- a ribbon sits top or
    # bottom, never start or end.
    def validate!(value, context: nil, allowed: EDGES)
      return nil if value.nil?

      symbol = value.to_s.to_sym
      return symbol if allowed.include?(symbol)

      where = context ? " for #{context}" : ""
      list = allowed.map(&:inspect).join(", ")
      raise ArgumentError, "unknown position #{value.inspect}#{where} — use #{list}"
    end
  end
end
