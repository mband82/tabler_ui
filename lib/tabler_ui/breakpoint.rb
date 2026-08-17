# frozen_string_literal: true

module TablerUi
  # Shared breakpoint vocabulary for components that need a responsive
  # variant of one of their classes (e.g. a sidebar that collapses below a
  # given width).
  #
  # Mirrors Bootstrap/Tabler's own breakpoint names, sm/md/lg/xl/xxl.
  #
  # Like TablerUi::Color and TablerUi::Align, an unrecognised value raises
  # rather than falling back: a silently ignored breakpoint: "mdd" is a
  # subtle layout regression with nothing pointing at the cause.
  module Breakpoint
    ALL = %w[sm md lg xl xxl].freeze

    module_function

    def valid?(value)
      return true if value.nil?

      ALL.include?(value.to_s)
    end

    # Returns the breakpoint as a String, or raises ArgumentError naming the
    # offender and listing the valid values. Passing nil returns nil (the
    # breakpoint is optional).
    def validate!(value, context: nil)
      return nil if value.nil?

      value = value.to_s
      return value if ALL.include?(value)

      where = context ? " for #{context}" : ""
      raise ArgumentError, "unknown breakpoint #{value.inspect}#{where} — valid: #{ALL.join(', ')}"
    end
  end
end
