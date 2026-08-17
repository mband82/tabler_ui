# frozen_string_literal: true

module TablerUi
  # Shared alignment vocabulary for components that position a floating element
  # (dropdown menus today).
  #
  # Uses Bootstrap's own terms, :start and :end, rather than left/right. Those
  # were the previous vocabulary and disagreed between components -- the
  # standalone dropdown compared against the string "right" while navbar's
  # nested one compared against the symbol :end, so passing either form to the
  # wrong component silently did nothing.
  #
  # Like TablerUi::Color, an unrecognised value raises rather than falling back:
  # a silently ignored align: "right" is a subtle visual regression with nothing
  # pointing at the cause.
  module Align
    VALID = %i[start end].freeze

    module_function

    def valid?(value)
      return true if value.nil?

      VALID.include?(value.to_s.to_sym)
    end

    # Returns :start or :end. nil means :start (alignment is optional).
    # Anything else raises ArgumentError naming the offender and the component.
    def validate!(value, context: nil)
      return :start if value.nil?

      symbol = value.to_s.to_sym
      return symbol if VALID.include?(symbol)

      where = context ? " for #{context}" : ""
      raise ArgumentError, "unknown align #{value.inspect}#{where} — use :start or :end"
    end
  end
end
