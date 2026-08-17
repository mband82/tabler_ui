# frozen_string_literal: true

module TablerUi
  module Tabs
    # Tabs component for Tabler UI. Renders a `ul.nav` of tab links plus a
    # matching `.tab-content` pane per tab. Builder-style: the block yields
    # the component itself, and tabs are added via #tab.
    #
    # @example Basic usage with block
    #   <%= tabler_ui.tabs("my-tabs") do |tabs| %>
    #     <% tabs.tab("First Tab", icon: "home") do %>
    #       Content for first tab
    #     <% end %>
    #     <% tabs.tab("Second Tab") do %>
    #       Content for second tab
    #     <% end %>
    #   <% end %>
    #
    # @example Card-style / pills / underline
    #   <%= tabler_ui.tabs("card-tabs", style: :card) do |tabs| %>
    #     ...
    #   <% end %>
    #
    # @example Badge as text (badge component's own default colour) or
    #   forwarded badge options
    #   <% tabs.tab("Inbox", badge: "3") %>
    #   <% tabs.tab("Inbox", badge: { text: "3", color: "red" }) %>
    #
    # @example Rule 5 hooks -- component-level and per-tab
    #   <%= tabler_ui.tabs("my-tabs", html: { class: "mb-3" },
    #                       nav_html: { class: "mb-0" },
    #                       content_html: { class: "p-2" }) do |tabs| %>
    #     <% tabs.tab("First", html: { class: "fw-bold" }) %>
    #     <% tabs.tab("Second", html: ->(tab) { { class: "text-danger" } if tab.title == "Second" }) %>
    #   <% end %>
    class Component
      include TablerUi::Base
      builder_style!

      # :html holds the caller's *raw* per-tab hook (Hash or Proc taking the
      # tab), not resolved attributes -- see #tab_attributes.
      Tab = Struct.new(:id, :title, :icon, :badge, :active, :content, :html, keyword_init: true)

      attr_reader :id, :style, :tabs

      # @param id [String] Unique ID for the tabs container, used as the base
      #   for each tab pane's anchor id ("#{id}-tab-1", ...). Mandatory --
      #   Bootstrap's tab JS needs stable anchor targets.
      # @param options [Hash]
      # @option options [Symbol, String] :style Tab style -- :tabs (default), :pills, :card, :underline
      # @option options [Hash] :html         Rule 5 HTML hook for the outer wrapper (part :root)
      # @option options [Hash] :nav_html     Rule 5 HTML hook for the `ul.nav` (part :nav)
      # @option options [Hash] :content_html Rule 5 HTML hook for the `.tab-content` (part :content)
      def initialize(id, options = {})
        @id = id
        @style = (options[:style] || :tabs).to_sym
        @tabs = []
        @tab_counter = 0

        initialize_html_options(options)
      end

      # Adds a tab.
      #
      # @param title [String] Tab title text
      # @param options [Hash]
      # @option options [String] :icon Optional Tabler icon name, rendered via tabler_ui.icon
      # @option options [String, Hash] :badge Badge text (String -- rendered
      #   with the badge component's own default colour) or a Hash of options
      #   forwarded straight to the badge component, e.g. { text: "3", color: "red" }
      # @option options [Boolean] :active Whether this tab is initially active
      #   (the first tab added is active by default unless a later tab is
      #   explicitly marked active: true)
      # @option options [Hash, #call] :html Rule 5 HTML hook for this tab's
      #   `a.nav-link` (part :tab) -- a plain Hash, or a callable taking the tab
      # @param block [Proc] Content block for the tab panel, captured in the template
      # @return [String] empty string, to avoid stray output in a capture context
      def tab(title, options = {}, &block)
        builder_argument!(title, :title, builder: :tab)

        @tab_counter += 1
        tab_id = "#{@id}-tab-#{@tab_counter}"

        is_active = options[:active].nil? ? @tabs.empty? : options[:active]

        @tabs << Tab.new(
          id: tab_id,
          title: title,
          icon: options[:icon],
          badge: options[:badge],
          active: is_active,
          content: block,
          html: options[:html]
        )

        ""
      end

      # @return [Boolean] whether there are any tabs
      def any?
        @tabs.any?
      end

      # @return [Hash] attributes for the outer wrapper (part :root)
      def root_attributes
        html_for(:root, class: "tabs")
      end

      # @return [Hash] attributes for the `ul.nav` (part :nav)
      def nav_attributes
        html_for(:nav, class: nav_classes)
      end

      # @return [Hash] attributes for the `.tab-content` (part :content)
      def content_attributes
        html_for(:content, class: "tab-content")
      end

      # @param tab [Tab] the tab being rendered
      # @return [Hash] attributes for this tab's `a.nav-link` (part :tab).
      #   Tabs repeat, so unlike the component-level hooks this resolves per
      #   tab: the tab's own :html (Hash or Proc taking the tab) is loaded
      #   into the shared html_for storage just before resolving, then
      #   handed to html_for as normal.
      def tab_attributes(tab)
        @tabler_ui_html_options[:tab] = tab.html
        html_for(:tab, { class: tab_link_classes(tab) }, tab)
      end

      # @param tab [Tab] the tab being rendered
      # @return [Hash] options forwarded to the badge component for this
      #   tab's badge -- a String becomes { text: ... }, a Hash passes
      #   straight through.
      def badge_options_for(tab)
        tab.badge.is_a?(Hash) ? tab.badge : { text: tab.badge }
      end

      private

      def tab_link_classes(tab)
        classes = ["nav-link"]
        classes << "active" if tab.active
        classes.join(" ")
      end

      def nav_classes
        classes = ["nav"]

        case style
        when :pills
          classes << "nav-pills"
        when :card
          classes << "nav-tabs" << "card-header-tabs"
        when :underline
          classes << "nav-tabs" << "nav-tabs-alt"
        else
          classes << "nav-tabs"
        end

        classes.join(" ")
      end
    end
  end
end
