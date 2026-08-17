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
    # @example Rule 5 hooks
    #   <%= tabler_ui.alert text: "Saved!", html: { class: "mb-4" },
    #                       title: "Done", title_html: { class: "text-uppercase" },
    #                       icon_html: { data: { testid: "alert-icon" } } %>
    class Component
      include TablerUi::Base

      attr_reader :text, :color, :title, :icon, :dismissible, :important, :url, :link_text

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
      # @option options [Hash]    :html        Rule 5 HTML hook for the root .alert element (part :root)
      # @option options [Hash]    :title_html  Rule 5 HTML hook for the .alert-title (part :title),
      #   only applied when a title renders
      # @option options [Hash]    :icon_html   Rule 5 HTML hook for the icon wrapper (part :icon),
      #   only applied when an icon renders
      def initialize(options = {})
        @text = options[:text]
        @color = TablerUi::Color.validate!(options[:color], context: "alert") || "info"
        @title = options[:title]
        @icon = options[:icon]
        @dismissible = options[:dismissible]
        @important = options[:important]
        @url = options[:url]
        @link_text = options[:link_text] || "Learn more"

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
      #   with whatever the caller supplied via html:.
      def root_attributes
        html_for(:root, class: alert_classes, role: "alert")
      end

      # @return [Hash] attributes for the .alert-title (part :title), merged with
      #   whatever the caller supplied via title_html:. Only used when title.present?.
      def title_attributes
        html_for(:title, class: "alert-title")
      end

      # @return [Hash] attributes for the icon wrapper (part :icon), merged with
      #   whatever the caller supplied via icon_html:. Only used when has_icon?.
      def icon_attributes
        html_for(:icon, class: "alert-icon-wrapper")
      end

      private

      def alert_classes
        classes = ["alert", "alert-#{color}"]
        classes << "alert-dismissible" if dismissible
        classes << "alert-important" if important
        classes.join(" ")
      end
    end
  end
end
