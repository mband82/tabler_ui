# frozen_string_literal: true

module TablerUi
  # Merges caller-supplied HTML attributes over a component's own defaults.
  module HtmlOptions
    module_function

    def merge_html(base, overrides)
      base = (base || {}).transform_keys(&:to_sym)
      overrides = (overrides || {}).transform_keys(&:to_sym)

      merged = base.merge(overrides)

      merged[:class] = merge_class(base[:class], overrides[:class]) if base.key?(:class) || overrides.key?(:class)
      merged[:data] = merge_deep(base[:data], overrides[:data]) if base.key?(:data) || overrides.key?(:data)
      merged[:aria] = merge_deep(base[:aria], overrides[:aria]) if base.key?(:aria) || overrides.key?(:aria)

      merged
    end

    def merge_html!(base, *overrides)
      overrides.compact.reduce(base) { |acc, override| merge_html(acc, override) }
    end

    def merge_class(base, overrides)
      [base, overrides].flatten.compact.flat_map { |c| c.to_s.split(/\s+/) }
                        .reject(&:empty?).uniq.join(" ")
    end
    private_class_method :merge_class

    def merge_deep(base, overrides)
      base = (base || {}).transform_keys(&:to_sym)
      overrides = (overrides || {}).transform_keys(&:to_sym)
      base.merge(overrides)
    end
    private_class_method :merge_deep
  end
end
