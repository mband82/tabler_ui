# frozen_string_literal: true

module TablerUi
  module Alert
    # Alert component for Tabler UI
    # Displays contextual feedback messages
    #
    # @example Basic usage
    #   <%= tabler_ui.alert color: "success", text: "Your changes have been saved!" %>
    #
    # @example With title and dismissible
    #   <%= tabler_ui.alert color: "danger", title: "Error", text: "Something went wrong.", dismissible: true %>
    #
    # @example Important alert
    #   <%= tabler_ui.alert color: "warning", text: "Your trial expires in 3 days.", important: true %>
    #
    # @example With icon
    #   <%= tabler_ui.alert color: "info", text: "New update available.", icon: "download" %>
    #
    # @example With a rich body via the body slot
    #   <%= tabler_ui.alert color: "success" do |slots| %>
    #     <% slots.body do %>
    #       <strong>Success!</strong> Your account has been created.
    #     <% end %>
    #   <% end %>
    #
    # @example With an action link
    #   <%= tabler_ui.alert color: "info", text: "New update available.", url: "/changelog", link_text: "See what's new" %>
    #
    # @example HTML attributes
    #   <%= tabler_ui.alert text: "Saved!", html: { class: "mb-4" },
    #                       title: "Done", title_html: { class: "text-uppercase" },
    #                       icon_html: { data: { testid: "alert-icon" } } %>
    #
    # @example link_html: and dismiss_html:
    #   <%= tabler_ui.alert text: "New update available.", url: "/changelog",
    #                       link_html: { data: { testid: "changelog-link" } },
    #                       dismissible: true, dismiss_html: { class: "hook-extra-class" } %>
    class Component
      include TablerUi::Base

      attr_reader :text, :color, :title, :icon, :dismissible, :important, :url, :link_text,
                  :minor, :link_style

      LINK_STYLES = %i[link action].freeze

      # @param options [Hash]
      # @option options [String]  :color       Alert color -- validated against
      #   TablerUi::Color (Tabler palette + Bootstrap semantic names). Defaults to "info".
      # @option options [String, nil] :title   Optional alert title
      # @option options [String, nil] :text    Alert body text (simple string case; see also the
      #   :body slot for rich content)
      # @option options [String, Boolean, nil] :icon Tabler icon name, or false to suppress the
      #   color's default icon
      # @option options [Boolean] :dismissible Whether the alert can be dismissed (default: false)
      # @option options [Boolean] :important   Important style with colored background (default: false)
      # @option options [String, nil] :url     Optional action link URL
      # @option options [String, nil] :link_text Action link text (default: "Learn more")
      # @option options [Boolean] :minor       Transparent background, bordered style (default: false)
      # @option options [Symbol]  :link_style  :link (default, bold underline-free) or :action
      #   (underlined, no bold) for the action link's style
      # @option options [Hash]    :html        HTML attributes for the root .alert element (part :root)
      # @option options [Hash]    :title_html  HTML attributes for the .alert-heading (part :title),
      #   only applied when a title renders
      # @option options [Hash]    :icon_html   HTML attributes for the icon's root <svg>
      #   (part :icon) -- there is no wrapper element, so the hook lands directly on the
      #   svg. Only applied when an icon renders.
      # @option options [Hash]    :link_html   HTML attributes for the `.alert-link`/`.alert-action`
      #   action link (part :link). Only applied when :url renders one.
      # @option options [Hash]    :dismiss_html HTML attributes for the `.btn-close` dismiss link
      #   (part :dismiss), only applied when :dismissible renders one. See #dismiss_attributes.
      def initialize(options = {})
        @text = options[:text]
        @color = TablerUi::Color.validate!(options[:color], extra: TablerUi::Color::MUTED, context: "alert") || "info"
        @title = options[:title]
        @icon = options[:icon]
        @dismissible = options[:dismissible]
        @important = options[:important]
        @url = options[:url]
        @link_text = options[:link_text] || "Learn more"
        @minor = options[:minor]
        @link_style = validate_link_style!(options[:link_style])

        initialize_html_options(options)
      end

      # @return [String, nil] icon name for the color, or the caller's own :icon override
      def default_icon
        return nil if icon == false
        return icon if icon.is_a?(String)

        case color
        when "success" then "check"
        when "info" then "info-circle"
        when "warning" then "alert-triangle"
        when "danger" then "alert-circle"
        else nil
        end
      end

      # @return [Boolean] whether the alert has an icon
      def has_icon?
        icon != false && default_icon.present?
      end

      # @return [Hash] attributes for the root .alert element (part :root), merged
      #   with whatever the caller supplied via html:. Carries
      #   `data-controller="tabler-ui--alert"` when dismissible -- folded in
      #   here (rather than spread separately in the ERB) since it is just
      #   another attribute on the same element and html_for already knows
      #   how to merge a caller's own `data:` under it without collision
      #   (`data-controller` is a literal attribute, not nested under the
      #   `data:` hook key).
      def root_attributes
        defaults = { class: alert_classes, role: "alert" }
        defaults[:"data-controller"] = "tabler-ui--alert" if dismissible

        html_for(:root, defaults)
      end

      # @return [Hash] attributes for the .alert-heading (part :title), merged with
      #   whatever the caller supplied via title_html:. Only used when title.present?.
      #   Tabler defines .alert-heading (tabler.css) for margin/font-weight; the
      #   previous "alert-title" class matched no CSS at all.
      def title_attributes
        html_for(:title, class: "alert-heading")
      end

      # @return [Hash] attributes for the icon (part :icon), merged with whatever
      #   the caller supplied via icon_html:. Only used when has_icon?. This is
      #   passed straight through as the `html:` hook to the icon component
      #   itself -- there is no wrapper <div> any more, so the hook lands on the
      #   rendered icon's own root <svg>, which is the element that actually
      #   needs to be a direct flex child of .alert. :class contributes the real
      #   .alert-icon class (tabler.css), which sets the icon's color/size.
      def icon_attributes
        html_for(:icon, class: "alert-icon")
      end

      # @return [String] CSS class for the action link, based on link_style
      def link_class
        link_style == :action ? "alert-action" : "alert-link"
      end

      # @return [Hash] attributes for the action `<a>` (part :link), merged
      #   with whatever the caller supplied via link_html:. Only used when
      #   url.present?.
      def link_attributes
        html_for(:link, class: link_class, href: url)
      end

      # @return [String] translated aria-label for the `.btn-close`
      def close_label
        I18n.t("tabler_ui.alert.close")
      end

      # @return [Hash] attributes for the `.btn-close` dismiss `<a>` (part
      #   :dismiss), merged with whatever the caller supplied via
      #   dismiss_html:. Only used when dismissible. The aria-label is
      #   translated (tabler_ui.alert.close), matching modal's and toast's
      #   close buttons -- see config/locales/en.yml.
      def dismiss_attributes
        html_for(:dismiss, class: "btn-close", "data-bs-dismiss": "alert", "aria-label": close_label)
      end

      private

      def alert_classes
        classes = ["alert", "alert-#{color}"]
        classes << "alert-dismissible" if dismissible
        classes << "alert-important" if important
        classes << "alert-minor" if minor
        classes.join(" ")
      end

      def validate_link_style!(value)
        return :link if value.nil?

        value = value.to_sym
        return value if LINK_STYLES.include?(value)

        raise ArgumentError, "unknown link_style #{value.inspect} for alert — valid: #{LINK_STYLES.join(', ')}"
      end
    end
  end
end
