# frozen_string_literal: true

module TablerUi
  module StatCard
    # Stat card component for Tabler UI. Displays a labeled metric with an
    # optional trend indicator, icon, description and "Details" link.
    #
    # @example Basic usage
    #   <%= tabler_ui.stat_card label: "Sales", value: "456", icon: "shopping-cart" %>
    #
    # @example With a positive trend
    #   <%= tabler_ui.stat_card label: "Sales", value: "456", trend: 12 %>
    #
    # @example With a negative trend, description and Details link
    #   <%= tabler_ui.stat_card label: "New clients", value: "18", trend: -8,
    #                          description: "vs. last month", url: "/clients" %>
    #
    # @example Colored icon
    #   <%= tabler_ui.stat_card label: "Revenue", value: "$9,600", icon: "currency-dollar", color: "green" %>
    #
    # @example Rule 5 hooks
    #   <%= tabler_ui.stat_card label: "Sales", value: "456", icon: "shopping-cart",
    #                          html: { class: "mb-3" },
    #                          body_html: { data: { testid: "sales-card" } },
    #                          value_html: { class: "fw-bold" },
    #                          icon_html: { class: "avatar-rounded" },
    #                          link_html: { class: "ms-2" } %>
    class Component
      include TablerUi::Base

      attr_reader :label, :value, :icon, :trend, :description, :color, :url

      # @param options [Hash]
      # @option options [String]           :label       Small header text above the trend
      # @option options [String]           :value       The headline metric
      # @option options [String]           :icon        Tabler icon name, rendered in a colored box
      # @option options [String]           :trend       Percentage trend. Positive renders green with an
      #   up arrow, negative renders red with a down arrow. Zero/nil renders no trend indicator at all.
      # @option options [String]           :description Small text under the value
      # @option options [String]           :color       Color variant for the icon box -- validated against
      #   TablerUi::Color (Tabler palette + Bootstrap semantic names). Defaults to "primary".
      # @option options [String]           :url         When present, renders a "Details" link
      # @option options [Hash]             :html        Rule 5 HTML hook for the outer <div class="card"> (part :root)
      # @option options [Hash]             :body_html   Rule 5 HTML hook for the <div class="card-body"> (part :body)
      # @option options [Hash]             :value_html  Rule 5 HTML hook for the value element (part :value)
      # @option options [Hash]             :icon_html   Rule 5 HTML hook for the icon badge (part :icon),
      #   only rendered when icon: is present
      # @option options [Hash]             :link_html   Rule 5 HTML hook for the Details link (part :link),
      #   only rendered when url: is present
      def initialize(options = {})
        @label = options[:label]
        @value = options[:value]
        @icon = options[:icon]
        @trend = options[:trend]
        @description = options[:description]
        @color = TablerUi::Color.validate!(options[:color], context: "stat_card")
        @url = options[:url]

        initialize_html_options(options)
      end

      # @return [Boolean] whether the value has an icon to render in the colored icon box
      def icon?
        @icon.present?
      end

      # @return [Boolean] whether the "Details" link should render
      def link?
        @url.present?
      end

      # @return [Integer, nil] the trend as an Integer, or nil when absent or
      #   zero -- zero renders no trend indicator at all, same as a nil/blank trend
      def trend_value
        return nil unless @trend.present?

        int = @trend.to_i
        int.zero? ? nil : int
      end

      # @return [Boolean] whether a trend indicator should render
      def trend?
        trend_value.present?
      end

      # @return [Boolean] true when the trend is positive
      def trend_positive?
        trend? && trend_value.positive?
      end

      # @return [String] "green" for a positive trend, "red" for a negative one
      def trend_color
        return nil unless trend?

        trend_positive? ? "green" : "red"
      end

      # @return [String] the Tabler icon name for the trend arrow
      def trend_icon
        return nil unless trend?

        trend_positive? ? "trending-up" : "trending-down"
      end

      # @return [String] "+" for a positive trend, "" otherwise
      def trend_prefix
        trend_positive? ? "+" : ""
      end

      # @return [String] color used for the icon box, defaulting to "primary"
      def icon_color
        @color || "primary"
      end

      # @return [Hash] attributes for the outer <div> (part :root), merged
      #   with whatever the caller supplied via html:.
      def root_attributes
        html_for(:root, class: "card")
      end

      # @return [Hash] attributes for the <div class="card-body"> (part :body),
      #   merged with whatever the caller supplied via body_html:.
      def body_attributes
        html_for(:body, class: "card-body")
      end

      # @return [Hash] attributes for the value element (part :value), merged
      #   with whatever the caller supplied via value_html:.
      def value_attributes
        html_for(:value, class: "h1 mb-0")
      end

      # @return [Hash] attributes for the icon badge (part :icon), merged
      #   with whatever the caller supplied via icon_html:. Only relevant
      #   when icon? is true.
      def icon_attributes
        html_for(:icon, class: "avatar bg-#{icon_color}-lt me-3")
      end

      # @return [Hash] attributes for the Details link (part :link), merged
      #   with whatever the caller supplied via link_html:. Only relevant
      #   when link? is true.
      def link_attributes
        html_for(:link, class: "btn btn-sm btn-outline-primary", href: @url)
      end
    end
  end
end
