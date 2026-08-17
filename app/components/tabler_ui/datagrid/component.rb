# frozen_string_literal: true

module TablerUi
  module Datagrid
    # Datagrid component for Tabler UI. Renders a `.datagrid` of label/value
    # pairs, each a `.datagrid-item` with a `.datagrid-title` and
    # `.datagrid-content`. Builder-style: the block yields the component
    # itself, and items are added via `#item`.
    #
    # @example Basic usage
    #   <%= tabler_ui.datagrid do |dg| %>
    #     <% dg.item "Name", content: "Ada Lovelace" %>
    #     <% dg.item "Bio" do %>
    #       <strong>Mathematician</strong>
    #     <% end %>
    #   <% end %>
    #
    # @example items: passed directly at construction
    #   <%= tabler_ui.datagrid items: [{ title: "Name", content: "Ada" }] %>
    #
    # @example Rule 5 hooks
    #   <%= tabler_ui.datagrid html: { class: "mb-4" },
    #                          item_html: ->(item) { item[:title] == "Name" ? { class: "fw-bold" } : {} },
    #                          title_html: { class: "text-muted" },
    #                          content_html: { class: "text-end" } do |dg| %>
    #     <% dg.item "Name", content: "Ada" %>
    #   <% end %>
    class Component
      include TablerUi::Base
      builder_style!

      attr_reader :items

      # @param options [Hash]
      # @option options [Array<Hash>] :items Pre-built items, each a Hash with
      #   `:title` and `:content` (default: [])
      # @option options [Hash]           :html         Rule 5 HTML hook for the outer `.datagrid` (part :root)
      # @option options [Hash, Proc]     :item_html    Rule 5 HTML hook for each `.datagrid-item` (part :item).
      #   Either a plain Hash (applied to every item) or a callable taking the
      #   item and returning a Hash.
      # @option options [Hash, Proc]     :title_html   Rule 5 HTML hook for each `.datagrid-title` (part :title)
      # @option options [Hash, Proc]     :content_html Rule 5 HTML hook for each `.datagrid-content` (part :content)
      def initialize(options = {})
        @items = options[:items] || []

        initialize_html_options(options)
      end

      # Adds an item to the datagrid.
      #
      # @param title [String] mandatory item title
      # @param options [Hash]
      # @option options [String] :content Item content. Ignored if a block is given.
      # @param block [Proc] Item content, captured at render time. Takes
      #   precedence over options[:content] when both are given.
      def item(title, options = {}, &block)
        builder_argument!(title, :title, builder: :item)

        @items << {
          title: title,
          content: options[:content],
          block: block,
        }
      end

      # @return [Boolean] whether there are any items to render
      def has_items?
        @items.any?
      end

      # @return [Hash] attributes for the outer element (part :root)
      def root_attributes
        html_for(:root, class: "datagrid")
      end

      # @param item [Hash] the current item being rendered
      # @return [Hash] attributes for this item's wrapper (part :item)
      def item_attributes(item)
        html_for(:item, { class: "datagrid-item" }, item)
      end

      # @param item [Hash] the current item being rendered
      # @return [Hash] attributes for this item's title (part :title)
      def title_attributes(item)
        html_for(:title, { class: "datagrid-title" }, item)
      end

      # @param item [Hash] the current item being rendered
      # @return [Hash] attributes for this item's content (part :content)
      def content_attributes(item)
        html_for(:content, { class: "datagrid-content" }, item)
      end
    end
  end
end
