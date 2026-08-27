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
    # @example HTML attributes -- component-level and per-tab
    #   <%= tabler_ui.tabs("my-tabs", html: { class: "mb-3" },
    #                       nav_html: { class: "mb-0" },
    #                       content_html: { class: "p-2" }) do |tabs| %>
    #     <% tabs.tab("First", html: { class: "fw-bold" }) %>
    #     <% tabs.tab("Second", html: ->(tab) { { class: "text-danger" } if tab.title == "Second" },
    #                 pane_html: { class: "p-3" }) %>
    #   <% end %>
    class Component
      include TablerUi::Base
      builder_style!

      # :html/:pane_html hold the caller's *raw* per-tab hooks (Hash or Proc
      # taking the tab), not resolved attributes -- see #tab_attributes /
      # #pane_attributes. :auth is the tab's resolved (post-inheritance)
      # `auth:` value (CLAUDE.md rule 8) -- stored for completeness, though
      # only authorized tabs ever make it into @tabs in the first place.
      Tab = Struct.new(:id, :title, :icon, :badge, :active, :content, :html, :pane_html, :auth, keyword_init: true)

      STYLES = %i[tabs pills card underline bordered segmented].freeze

      attr_reader :id, :style, :tabs, :fill, :justified, :vertical

      # @param id [String] Unique ID for the tabs container, used as the base
      #   for each tab pane's anchor id ("#{id}-tab-1", ...). Mandatory --
      #   Bootstrap's tab JS needs stable anchor targets.
      # @param options [Hash]
      # @option options [Symbol, String] :style Tab style -- :tabs (default), :pills,
      #   :card, :underline, :bordered, :segmented. Anything else raises ArgumentError
      #   naming the component and the valid values.
      # @option options [Boolean] :fill Adds `nav-fill` -- equal-width items that fill
      #   the available space. Mutually exclusive with :justified.
      # @option options [Boolean] :justified Adds `nav-justified` -- equal-width items
      #   that fill the available space, each within its own equal column. Mutually
      #   exclusive with :fill.
      # @option options [Boolean] :vertical Adds `nav-segmented-vertical`. Only valid
      #   together with style: :segmented -- raises ArgumentError otherwise.
      # @option options [Hash] :html         HTML attributes for the outer wrapper (part :root)
      # @option options [Hash] :nav_html     HTML attributes for the `ul.nav` (part :nav)
      # @option options [Hash] :content_html HTML attributes for the `.tab-content` (part :content)
      def initialize(id, options = {})
        @id = id
        @style = validate_style(options[:style])
        @fill = options[:fill]
        @justified = options[:justified]
        @vertical = options[:vertical]
        @tabs = []
        @tab_counter = 0

        validate_layout_options!

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
      # @option options [Hash, #call] :html HTML attributes for this tab's
      #   `a.nav-link` (part :tab) -- a plain Hash, or a callable taking the tab
      # @option options [Hash, #call] :pane_html HTML attributes for this
      #   tab's own `.tab-pane` content panel (part :pane) -- a plain Hash,
      #   or a callable taking the tab, same mechanism as :html -- see #pane_attributes
      # @option options [Object] :auth Per-tab authorization value (CLAUDE.md
      #   rule 8) -- checked against the globally configured auth_method.
      #   Defaults to tabs' own :auth when omitted. An unauthorized tab is not
      #   appended, so it never counts toward "is this the first tab"
      #   (active-by-default) and the id counter only advances over tabs that
      #   actually render.
      # @param block [Proc] Content block for the tab panel, captured in the template
      # @return [String, nil] empty string, to avoid stray output in a capture
      #   context; nil (no-op) if :auth denied it
      def tab(title, options = {}, &block)
        effective_auth = options.key?(:auth) ? options[:auth] : auth
        return unless TablerUi::Authorization.authorized?(effective_auth)

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
          html: options[:html],
          pane_html: options[:pane_html],
          auth: effective_auth
        )

        ""
      end

      # @return [Boolean] whether there are any tabs
      def any?
        @tabs.any?
      end

      # @return [Boolean] whether style: :segmented is in effect. `.nav-segmented`
      #   sizes its `.nav-link` children as *direct* flex children, so the template
      #   drops the `li.nav-item` wrapper used by every other style when this is true.
      def segmented?
        style == :segmented
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
      # @return [Hash] attributes for this tab's `.tab-pane` content panel
      #   (part :pane). Same per-tab mechanism as #tab_attributes -- the
      #   tab's own :pane_html (Hash or Proc taking the tab) is loaded into
      #   the shared html_for storage just before resolving.
      def pane_attributes(tab)
        @tabler_ui_html_options[:pane] = tab.pane_html
        html_for(:pane, { class: pane_classes(tab) }, tab)
      end

      # @param tab [Tab] the tab being rendered
      # @return [Hash] options forwarded to the badge component for this
      #   tab's badge -- a String becomes { text: ... }, a Hash passes
      #   straight through.
      def badge_options_for(tab)
        tab.badge.is_a?(Hash) ? tab.badge : { text: tab.badge }
      end

      private

      def validate_style(value)
        style = (value || :tabs).to_sym
        return style if STYLES.include?(style)

        raise ArgumentError,
              "unknown tabs style #{value.inspect} — valid: #{STYLES.join(', ')}"
      end

      def validate_layout_options!
        if fill && justified
          raise ArgumentError, "tabler_ui.tabs: fill: and justified: are mutually exclusive"
        end

        if vertical && style != :segmented
          raise ArgumentError, "tabler_ui.tabs: vertical: is only valid together with style: :segmented"
        end
      end

      def tab_link_classes(tab)
        classes = ["nav-link"]
        classes << "active" if tab.active
        classes.join(" ")
      end

      def pane_classes(tab)
        classes = ["tab-pane"]
        classes << "active" << "show" if tab.active
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
          classes << "nav-underline"
        when :bordered
          # Tabler's own style. The name is a trap: "bordered" does not mean
          # "boxed" -- it adds a full-width baseline divider across the whole
          # bar, plus a 2px underline on the active link.
          classes << "nav-bordered"
        when :segmented
          classes << "nav-segmented"
          classes << "nav-segmented-vertical" if vertical
        else
          classes << "nav-tabs"
        end

        classes << "nav-fill" if fill
        classes << "nav-justified" if justified

        classes.join(" ")
      end
    end
  end
end
