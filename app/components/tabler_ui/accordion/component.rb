# frozen_string_literal: true

module TablerUi
  module Accordion
    # Accordion component for Tabler UI. Renders a `.accordion` of stacked
    # `.accordion-item`s, each with a clickable `.accordion-header` and a
    # `.accordion-collapse` pane driven by Bootstrap's Collapse (via
    # `tabler-ui--collapse`, the same lifecycle controller the navbar's
    # collapsible nav already uses -- see collapse_controller.js). Builder
    # style: the block yields the component itself, and items are added via
    # #item.
    #
    # @example Basic usage with block -- single-open by default
    #   <%= tabler_ui.accordion("my-accordion") do |accordion| %>
    #     <% accordion.item("First item", open: true) do %>
    #       Content for the first item
    #     <% end %>
    #     <% accordion.item("Second item") do %>
    #       Content for the second item
    #     <% end %>
    #   <% end %>
    #
    # @example Multiple items open at once
    #   <%= tabler_ui.accordion("my-accordion", multiple: true) do |accordion| %>
    #     <% accordion.item("First", open: true) { "Content" } %>
    #     <% accordion.item("Second", open: true) { "Content" } %>
    #   <% end %>
    #
    # @example flush / inverted / accordion-tabs / plus toggle
    #   <%= tabler_ui.accordion("my-accordion", flush: true, inverted: true,
    #                           style: :tabs, toggle_style: :plus) do |accordion| %>
    #     ...
    #   <% end %>
    #
    # @example Rule 5 hooks -- component-level and per-item
    #   <%= tabler_ui.accordion("my-accordion", html: { class: "mb-3" }) do |accordion| %>
    #     <% accordion.item("First", icon: "home",
    #                        html: { class: "fw-bold" },
    #                        header_html: { class: "bg-light" },
    #                        body_html: { class: "p-2" }) { "Content" } %>
    #   <% end %>
    class Component
      include TablerUi::Base
      builder_style!

      # :html/:header_html/:body_html hold the caller's *raw* per-item hooks
      # (Hash or Proc taking the item), not resolved attributes -- see
      # #item_attributes, #item_header_attributes, #item_body_attributes.
      Item = Struct.new(:id, :header_id, :title, :icon, :open, :content,
                         :html, :header_html, :body_html, keyword_init: true)

      attr_reader :id, :flush, :inverted, :style, :toggle_style, :multiple, :items

      # @param id [String] Unique ID for the accordion container. Mandatory --
      #   it becomes the root element's own id, referenced by every item's
      #   `data-bs-parent="##{id}"` in single-open mode (see #multiple), so
      #   Bootstrap's Collapse can find and close the other open panes.
      # @param options [Hash]
      # @option options [Boolean] :flush    Removes the default borders/rounded corners (.accordion-flush)
      # @option options [Boolean] :inverted Moves the toggle icon before the title (.accordion-inverted)
      # @option options [Symbol]  :style    :tabs for the card-like accordion-tabs variant (default: plain)
      # @option options [Symbol]  :toggle_style Toggle icon: :chevron (default) or :plus
      # @option options [Boolean] :multiple Allow more than one item open at once (default: false --
      #   single-open, each pane closes its siblings via data-bs-parent)
      # @option options [Hash] :html Rule 5 HTML hook for the outer wrapper (part :root)
      def initialize(id, options = {})
        @id = id
        @flush = options[:flush]
        @inverted = options[:inverted]
        @style = options[:style]&.to_sym
        @toggle_style = (options[:toggle_style] || :chevron).to_sym
        @multiple = options[:multiple] || false
        @items = []
        @item_counter = 0

        initialize_html_options(options)
      end

      # Adds an item.
      #
      # @param title [String] Item title text
      # @param options [Hash]
      # @option options [Boolean] :open Whether this item starts expanded (default: false --
      #   see #validate! for why more than one :open in single-open mode raises)
      # @option options [String] :icon Optional Tabler icon name, rendered via tabler_ui.icon
      # @option options [Hash, #call] :html Rule 5 HTML hook for this item's
      #   `.accordion-button` (part :item) -- a plain Hash, or a callable taking the item
      # @option options [Hash, #call] :header_html Rule 5 HTML hook for this item's
      #   `.accordion-header` (part :item_header)
      # @option options [Hash, #call] :body_html Rule 5 HTML hook for this item's
      #   `.accordion-body` (part :item_body)
      # @param block [Proc] Content block for the item's body, captured in the template
      # @return [String] empty string, to avoid stray output in a capture context
      def item(title, options = {}, &block)
        builder_argument!(title, :title, builder: :item)

        @item_counter += 1
        item_id = "#{@id}-item-#{@item_counter}"

        @items << Item.new(
          id: item_id,
          header_id: "#{item_id}-header",
          title: title,
          icon: options[:icon],
          open: options[:open] || false,
          content: block,
          html: options[:html],
          header_html: options[:header_html],
          body_html: options[:body_html]
        )

        ""
      end

      # Called by TablerUi::Ui once the builder block has run and every item
      # is known. Two or more items marked open: true only makes sense in
      # :multiple mode -- in single-open mode it would statically render two
      # `.accordion-collapse.show` panes at once, which is broken markup
      # (Bootstrap's data-bs-parent only closes siblings on the next click,
      # not on initial render). Raising here -- rather than silently keeping
      # the first and dropping the rest -- surfaces the contradiction to the
      # caller instead of shipping a page that looks fine until the accordion
      # loads with two panes open.
      def validate!
        return if @multiple

        open_count = @items.count(&:open)
        return if open_count <= 1

        raise ArgumentError,
              "accordion##{@id} has #{open_count} items marked open: true, but multiple: true " \
              "was not set -- a single-open accordion can only start with one item open. " \
              "Pass multiple: true, or mark only one item open:."
      end

      # @return [Hash] attributes for the outer wrapper (part :root)
      def root_attributes
        html_for(:root, id: @id, class: accordion_classes)
      end

      # @param item [Item] the item being rendered
      # @return [Hash] attributes for this item's `.accordion-button` (part :item).
      #   Items repeat, so unlike the component-level hook this resolves per
      #   item: the item's own :html (Hash or Proc taking the item) is loaded
      #   into the shared html_for storage just before resolving, then
      #   handed to html_for as normal.
      def item_attributes(item)
        @tabler_ui_html_options[:item] = item.html
        html_for(:item, { class: button_classes(item) }, item)
      end

      # @param item [Item] the item being rendered
      # @return [Hash] attributes for this item's `.accordion-header` (part :item_header)
      def item_header_attributes(item)
        @tabler_ui_html_options[:item_header] = item.header_html
        html_for(:item_header, { class: "accordion-header" }, item)
      end

      # @param item [Item] the item being rendered
      # @return [Hash] attributes for this item's `.accordion-body` (part :item_body)
      def item_body_attributes(item)
        @tabler_ui_html_options[:item_body] = item.body_html
        html_for(:item_body, { class: "accordion-body" }, item)
      end

      # @param item [Item] the item being rendered
      # @return [String] classes for this item's `.accordion-collapse` pane.
      #   Structural only -- unlike :item/:item_header/:item_body this part
      #   has no dedicated hook, same as Tabs' `<li class="nav-item">`.
      def collapse_classes(item)
        classes = ["accordion-collapse", "collapse"]
        classes << "show" if item.open
        classes.join(" ")
      end

      # @return [String, nil] the `data-bs-parent` selector for every item's
      #   `.accordion-collapse`, or nil in :multiple mode (Rails' tag builder
      #   omits nil attributes, so the attribute itself disappears -- that's
      #   the single behavioural difference between single-open and :multiple).
      def parent_selector
        "##{@id}" unless @multiple
      end

      # @return [String] the toggle icon's Tabler icon name
      def toggle_icon
        @toggle_style == :plus ? "plus" : "chevron-down"
      end

      # @return [String] classes for the toggle icon
      def toggle_icon_classes
        classes = ["accordion-button-toggle"]
        classes << "accordion-button-toggle-plus" if @toggle_style == :plus
        classes.join(" ")
      end

      private

      def button_classes(item)
        classes = ["accordion-button"]
        classes << "collapsed" unless item.open
        classes.join(" ")
      end

      def accordion_classes
        classes = ["accordion"]
        classes << "accordion-flush" if flush
        classes << "accordion-tabs" if style == :tabs
        classes << "accordion-inverted" if inverted
        classes.join(" ")
      end
    end
  end
end
