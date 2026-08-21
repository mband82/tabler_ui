# frozen_string_literal: true

module TablerUi
  module SettingsPage
    # SettingsPage component for Tabler UI. Renders a `.card` with a sidebar
    # list-group of items on the left and a matching tab-pane per item on the
    # right. Builder-style: the block yields the component itself, and items
    # are added via #item.
    #
    # @example Basic usage with block
    #   <%= tabler_ui.settings_page("my-settings", title: "Settings") do |sp| %>
    #     <% sp.item("General", icon: "settings") do %>
    #       Content for general settings
    #     <% end %>
    #     <% sp.item("Security", icon: "shield", active: true) do %>
    #       Content for security settings
    #     <% end %>
    #   <% end %>
    #
    # @example HTML attributes -- component-level and per-item
    #   <%= tabler_ui.settings_page("my-settings",
    #                                html: { class: "mb-4" },
    #                                sidebar_html: { class: "bg-dark" },
    #                                content_html: { class: "p-0" }) do |sp| %>
    #     <% sp.item("General", html: { class: "fw-bold" }) do %>Content<% end %>
    #     <% sp.item("Security", html: ->(item) { { class: "text-danger" if item.title == "Security" } }) do %>
    #       Content
    #     <% end %>
    #   <% end %>
    class Component
      include TablerUi::Base
      builder_style!

      attr_reader :id, :title, :items

      Item = Struct.new(:id, :title, :icon, :active, :content, :html, keyword_init: true)

      # @param id [String] Unique ID for the settings container, used to
      #   namespace each item's list-group-item / tab-pane anchor pair.
      # @param options [Hash]
      # @option options [String] :title        Displayed above the sidebar navigation (default: "Settings")
      # @option options [Hash]   :html          HTML attributes for the outer `.card` (part :root)
      # @option options [Hash]   :sidebar_html  HTML attributes for the sidebar column/card-body (part :sidebar)
      # @option options [Hash]   :content_html  HTML attributes for the content area (part :content)
      def initialize(id, options = {})
        @id = id
        @title = options.fetch(:title, "Settings")
        @items = []
        @item_counter = 0

        initialize_html_options(options)
      end

      # Add a settings item to the component.
      #
      # @param title [String] Item title text
      # @param options [Hash]
      # @option options [String]  :icon   Optional Tabler icon name
      # @option options [Boolean] :active Whether this item is initially active
      #   (the first item added is active by default unless a later item is
      #   explicitly marked active: true)
      # @option options [Hash, Proc] :html HTML attributes for this item's own
      #   `a.list-group-item` (part :item). May be a plain Hash, or a callable
      #   taking the item and returning a Hash -- see #item_attributes.
      # @param block [Proc] Content block for the settings panel (stored as a
      #   Proc, captured in the template)
      def item(title, options = {}, &block)
        builder_argument!(title, :title, builder: :item)

        @item_counter += 1
        item_id = "#{@id}-item-#{@item_counter}"

        is_active = options[:active].nil? ? @items.empty? : options[:active]

        @items << Item.new(
          id: item_id,
          title: title,
          icon: options[:icon],
          active: is_active,
          content: block,
          html: options[:html]
        )

        ""
      end

      # @return [Boolean] whether there are any items
      def any?
        @items.any?
      end

      # @return [Hash] attributes for the outer element (part :root)
      def root_attributes
        html_for(:root, class: "card")
      end

      # @return [Hash] attributes for the sidebar column/card-body (part :sidebar)
      def sidebar_attributes
        html_for(:sidebar, class: "col-12 col-md-3 border-end card-body")
      end

      # @return [Hash] attributes for the content area (part :content)
      def content_attributes
        html_for(:content, class: "col-12 col-md-9 card-body")
      end

      # @return [Hash] attributes for a single item's `a.list-group-item`
      #   (part :item). Items repeat, so unlike the component-level hooks
      #   this resolves per item: the item's own :html (Hash or Proc taking
      #   the item) is loaded into the shared html_for storage just before
      #   resolving, then handed to html_for as normal.
      def item_attributes(item)
        @tabler_ui_html_options[:item] = item.html
        html_for(:item, { class: item_classes(item) }, item)
      end

      private

      def item_classes(item)
        classes = "list-group-item list-group-item-action d-flex align-items-center"
        classes += " active" if item.active
        classes
      end
    end
  end
end
