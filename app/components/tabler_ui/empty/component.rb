# frozen_string_literal: true

module TablerUi
  module Empty
    # Empty component for Tabler UI. Renders an `.empty` panel for no-results /
    # empty-state screens, with optional `.empty-img`, `.empty-icon`,
    # `.empty-header`, `.empty-title`, `.empty-subtitle` and `.empty-action`
    # parts. All parts are siblings in a centred flex column, not nested.
    #
    # `icon:` and `image:` are rendered through the dispatcher
    # (`tabler_ui.icon` / `tabler_ui.illustration`) rather than by
    # instantiating `TablerUi::Icon::Component` / `TablerUi::Illustration::Component`
    # directly -- see CLAUDE.md's component conventions.
    #
    # @example Basic usage -- title plus subtitle
    #   <%= tabler_ui.empty title: "No results found",
    #                        subtitle: "Try adjusting your search or filter." %>
    #
    # @example Illustration, title, action buttons
    #   <%= tabler_ui.empty image: "empty", title: "No results found" do |slots| %>
    #     <% slots.action do %>
    #       <%= tabler_ui.button text: "New item", url: "#" %>
    #     <% end %>
    #   <% end %>
    #
    # @example 404-style header, icon instead of illustration, bordered
    #   <%= tabler_ui.empty icon: "mood-empty", header: "404",
    #                        title: "Page not found", bordered: true %>
    #
    # @example A slot overrides its equivalent plain option
    #   <%= tabler_ui.empty image: "ignored" do |slots| %>
    #     <% slots.img do %><img src="/custom.svg" alt=""><% end %>
    #   <% end %>
    #
    # @example Rule 5 hooks
    #   <%= tabler_ui.empty title: "x", html: { class: "mb-4" },
    #                        title_html: { class: "text-danger" },
    #                        subtitle_html: { class: "text-muted" } %>
    #
    # Note: the block yields exactly one argument, the SlotContext --
    # `do |slots|`, not `do |empty, slots|`.
    class Component
      include TablerUi::Base

      attr_reader :title, :subtitle, :header, :icon, :image, :bordered

      # @param options [Hash]
      # @option options [String]  :title      Rendered as a `<p class="empty-title">`.
      # @option options [String]  :subtitle   Rendered as a `<p class="empty-subtitle">`.
      # @option options [String]  :header     Large lead text (e.g. an error code),
      #   rendered as a `<div class="empty-header">` when no `header` slot is given.
      # @option options [String]  :icon       Tabler icon name, rendered via
      #   `tabler_ui.icon` inside `.empty-icon` when no `icon` slot is given.
      # @option options [String]  :image      Tabler illustration name, rendered via
      #   `tabler_ui.illustration` inside `.empty-img` when no `img` slot is given.
      #   For an arbitrary external image/URL, use the `img` slot instead.
      # @option options [Boolean] :bordered   empty-bordered (default: false)
      # @option options [Hash]    :html          Rule 5 HTML hook for the outer `.empty` (part :root)
      # @option options [Hash]    :img_html      Rule 5 HTML hook for the `.empty-img` (part :img)
      # @option options [Hash]    :icon_html     Rule 5 HTML hook for the `.empty-icon` (part :icon)
      # @option options [Hash]    :header_html   Rule 5 HTML hook for the `.empty-header` (part :header)
      # @option options [Hash]    :title_html    Rule 5 HTML hook for the `.empty-title` (part :title)
      # @option options [Hash]    :subtitle_html Rule 5 HTML hook for the `.empty-subtitle` (part :subtitle)
      # @option options [Hash]    :action_html   Rule 5 HTML hook for the `.empty-action` (part :action)
      def initialize(options = {})
        @title = options[:title]
        @subtitle = options[:subtitle]
        @header = options[:header]
        @icon = options[:icon]
        @image = options[:image]
        @bordered = options[:bordered]

        initialize_html_options(options)
      end

      # @return [Hash] attributes for the outer element (part :root)
      def root_attributes
        html_for(:root, class: root_classes)
      end

      # @return [Hash] attributes for the `.empty-img` (part :img)
      def img_attributes
        html_for(:img, class: "empty-img")
      end

      # @return [Hash] attributes for the `.empty-icon` (part :icon)
      def icon_attributes
        html_for(:icon, class: "empty-icon")
      end

      # @return [Hash] attributes for the `.empty-header` (part :header)
      def header_attributes
        html_for(:header, class: "empty-header")
      end

      # @return [Hash] attributes for the `.empty-title` (part :title)
      def title_attributes
        html_for(:title, class: "empty-title")
      end

      # @return [Hash] attributes for the `.empty-subtitle` (part :subtitle)
      def subtitle_attributes
        html_for(:subtitle, class: "empty-subtitle")
      end

      # @return [Hash] attributes for the `.empty-action` (part :action)
      def action_attributes
        html_for(:action, class: "empty-action")
      end

      private

      def root_classes
        classes = ["empty"]
        classes << "empty-bordered" if @bordered
        classes.join(" ")
      end
    end
  end
end
