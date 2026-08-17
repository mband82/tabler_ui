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

    module_function

    def valid?(value)
      return false if value.nil?

      ALL.include?(value.to_s)
    end

    # Returns the colour as a String, or raises ArgumentError naming the
    # offender and listing the valid values. Passing nil returns nil (colour
    # is optional).
    def validate!(value, context: nil)
      return nil if value.nil?

      value = value.to_s
      return value if ALL.include?(value)

      where = context ? " for #{context}" : ""
      raise ArgumentError, "unknown color #{value.inspect}#{where} — valid: #{ALL.join(', ')}"
    end
  end
end
