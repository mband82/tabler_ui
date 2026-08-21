# frozen_string_literal: true

module TablerUi
  module Progress
    # Progress bar component for Tabler UI.
    #
    # @example Basic usage (percent defaults to 0)
    #   <%= tabler_ui.progress %>
    #   <%= tabler_ui.progress percent: 42 %>
    #
    # @example Auto color -- picks success/warning/danger from the percentage
    #   <%= tabler_ui.progress percent: 82, color: "auto" %>
    #
    # @example Striped + animated
    #   <%= tabler_ui.progress percent: 60, striped: true, animated: true %>
    #
    # @example Label row with the percentage
    #   <%= tabler_ui.progress percent: 60, label: "Uploading", show_percent: true %>
    #
    # @example Custom height and size
    #   <%= tabler_ui.progress percent: 30, height: "4px", size: :sm %>
    #
    # @example HTML attributes on all three parts
    #   <%= tabler_ui.progress percent: 50,
    #                          html: { class: "mb-3" },
    #                          bar_html: { data: { testid: "upload-bar" } },
    #                          label_html: { class: "mb-2" } %>
    class Component
      include TablerUi::Base

      # Magic `color:` value -- not a real Tabler/Bootstrap colour name, so it
      # bypasses TablerUi::Color.validate! entirely and instead picks a colour
      # from AUTO_THRESHOLDS at render time, based on `percent`.
      AUTO_COLOR = "auto"

      # Percent-based thresholds for color: "auto". >= danger threshold wins
      # over >= warning threshold; anything lower falls through to success.
      AUTO_THRESHOLDS = {
        danger: 90,
        warning: 75
      }.freeze

      attr_reader :percent, :color, :height, :label, :show_percent, :size, :striped, :animated,
                  :indeterminate, :separated

      # @param options [Hash]
      # @option options [Numeric] :percent Clamped to 0..100 (default: 0). Mutually
      #   exclusive with `indeterminate:` (raises ArgumentError if both given).
      # @option options [String] :color Tabler palette / Bootstrap semantic colour
      #   name (validated via TablerUi::Color, raises ArgumentError if unknown), or
      #   `"auto"` to resolve success/warning/danger from `percent`. Defaults to
      #   "primary".
      # @option options [String] :height CSS height for the outer bar, e.g. "8px"
      # @option options [String] :label Text shown in a label row above the bar
      # @option options [Boolean] :show_percent Show the rounded percentage --
      #   next to the label when `label:` is given, or as a visually-hidden
      #   span inside the bar otherwise
      # @option options [String, Symbol] :size :sm / :lg -- progress-<size>
      # @option options [Boolean] :striped .progress-bar-striped
      # @option options [Boolean] :animated .progress-bar-animated
      # @option options [Boolean] :indeterminate Switches to `.progress-bar-indeterminate`'s
      #   sweep animation. Omits `width` and `aria-valuenow` (value is unknown). Mutually
      #   exclusive with `percent:` (raises ArgumentError).
      # @option options [Boolean] :separated Adds `.progress-separated` to the track. No
      #   visible effect with a single bar -- only matters for stacked progress bars,
      #   which this component does not yet render.
      # @option options [Hash] :html HTML attributes for the outer .progress <div> (part :root)
      # @option options [Hash] :bar_html HTML attributes for the inner .progress-bar <div> (part :bar)
      # @option options [Hash] :label_html HTML attributes for the label row <div> (part :label),
      #   only rendered when label_row? is true
      def initialize(options = {})
        @indeterminate = options[:indeterminate]

        if @indeterminate && options.key?(:percent)
          raise ArgumentError, "progress: :percent is ignored when indeterminate: true is set -- pass only one"
        end

        @percent = clamp_percent(options.fetch(:percent, 0))
        @color = resolve_color(options[:color])
        @height = options[:height]
        @label = options[:label]
        @show_percent = options[:show_percent]
        @size = options[:size]
        @striped = options[:striped]
        @animated = options[:animated]
        @separated = options[:separated]

        initialize_html_options(options)
      end

      # @return [Boolean] whether the label row (above the bar) renders at all
      def label_row?
        @label.present?
      end

      # @return [Float] percent rounded to 1 decimal place, for display.
      def rounded_percent
        @percent.round(1)
      end

      # @return [Hash] attributes for the outer <div> (part :root), merged
      #   with whatever the caller supplied via html:.
      def root_attributes
        classes = ["progress"]
        classes << "progress-#{@size}" if @size.present?
        classes << "progress-separated" if @separated

        defaults = { class: classes.join(" ") }
        defaults[:style] = "height: #{@height};" if @height.present?

        html_for(:root, defaults)
      end

      # @return [Hash] attributes for the inner <div> (part :bar), merged
      #   with whatever the caller supplied via bar_html:. Carries the
      #   role/aria-* attributes a progress bar needs for accessibility --
      #   callers can still override any of them via bar_html:. When
      #   `indeterminate:` is set, the inline width style and aria-valuenow
      #   are omitted since the value is unknown -- role/aria-valuemin/
      #   aria-valuemax are still present.
      def bar_attributes
        classes = ["progress-bar", "bg-#{resolved_color}"]
        classes << "progress-bar-striped" if @striped
        classes << "progress-bar-animated" if @animated
        classes << "progress-bar-indeterminate" if @indeterminate

        aria = { valuemin: 0, valuemax: 100 }
        aria[:valuenow] = @percent unless @indeterminate

        defaults = { class: classes.join(" "), role: "progressbar", aria: aria }
        defaults[:style] = "width: #{@percent}%" unless @indeterminate

        html_for(:bar, defaults)
      end

      # @return [Hash] attributes for the label row <div> (part :label),
      #   merged with whatever the caller supplied via label_html:. Only
      #   meaningful when label_row? is true.
      def label_attributes
        html_for(:label, class: "d-flex mb-1")
      end

      private

      def clamp_percent(value)
        [[value.to_f, 0].max, 100].min.to_f
      end

      # nil -> default "primary"; "auto" bypasses TablerUi::Color entirely
      # (it is not a colour name); anything else is validated.
      def resolve_color(value)
        color = value.nil? ? "primary" : value.to_s

        return AUTO_COLOR if color == AUTO_COLOR

        TablerUi::Color.validate!(color, context: "progress")
      end

      # The actual bg-<color> suffix used on the bar: @color itself, unless
      # it's the "auto" magic value, in which case pick from AUTO_THRESHOLDS.
      def resolved_color
        return @color unless @color == AUTO_COLOR

        if @percent >= AUTO_THRESHOLDS[:danger]
          "danger"
        elsif @percent >= AUTO_THRESHOLDS[:warning]
          "warning"
        else
          "success"
        end
      end
    end
  end
end
