# frozen_string_literal: true

module TablerUi
  module Dropdown
    # Dropdown component for Tabler UI. Renders a Bootstrap dropdown menu.
    # Builder-style: the block yields the component itself, and menu entries
    # are added via #item, #divider, #header.
    #
    # @example Basic usage
    #   <%= tabler_ui.dropdown(label: "Actions") do |dropdown| %>
    #     <% dropdown.item("Edit", url: edit_path) %>
    #     <% dropdown.item("Delete", url: delete_path, method: :delete) %>
    #     <% dropdown.divider %>
    #     <% dropdown.item("Archive", url: archive_path) %>
    #   <% end %>
    #
    # @example Alignment and colour
    #   <%= tabler_ui.dropdown(label: "Actions", color: "danger", align: :end) do |dropdown| %>
    #     ...
    #   <% end %>
    #
    # @example HTML attributes -- component-level and per-item
    #   <%= tabler_ui.dropdown(label: "Actions", html: { class: "mb-3" },
    #                          toggle_html: { class: "btn-sm" },
    #                          menu_html: { class: "shadow" }) do |dropdown| %>
    #     <% dropdown.item("Edit", url: edit_path, html: { class: "fw-bold" }) %>
    #     <% dropdown.item("Delete", url: delete_path,
    #                       html: ->(item) { { class: "text-danger" } if item.title == "Delete" }) %>
    #   <% end %>
    class Component
      include TablerUi::Base
      builder_style!

      # Alignment vocabulary lives in TablerUi::Align, shared with Navbar.
      # :html holds the caller's *raw* per-item hook (Hash or Proc taking the
      # item), not resolved attributes -- see #item_attributes.
      Item = Struct.new(:type, :title, :url, :method, :active, :disabled, :icon, :html, keyword_init: true)

      # Maps :direction values onto the wrapper class that replaces the plain
      # "dropdown" class. These are alternatives, not additions -- Tabler
      # declares dropdown/dropup/dropend/dropstart/dropup-center/dropdown-center
      # as siblings in one shared `position: relative` rule, and Bootstrap's JS
      # reads whichever one is present on the toggle's parentNode to compute
      # Popper placement.
      DIRECTIONS = {
        "down" => "dropdown",
        "up" => "dropup",
        "end" => "dropend",
        "start" => "dropstart",
        "up-center" => "dropup-center",
        "down-center" => "dropdown-center"
      }.freeze

      attr_reader :label, :color, :align, :items, :direction, :dark, :scrollable, :arrow, :align_breakpoint

      # @param options [Hash]
      # @option options [String] :label Button text
      # @option options [String] :color Tabler colour name for the toggle button (default: "primary")
      # @option options [Symbol, String] :align Menu alignment -- :start (default) or :end
      #   (also accepted as strings). Other values, including "left"/"right", raise ArgumentError.
      # @option options [String] :direction Drop direction -- "down" (default), "up", "end",
      #   "start", "up-center" or "down-center". Replaces the wrapper's base "dropdown"
      #   class; anything else raises ArgumentError.
      # @option options [Boolean] :dark Adds `dropdown-menu-dark` to the menu.
      # @option options [Boolean] :scrollable Adds `dropdown-menu-scrollable` to the menu.
      # @option options [Boolean] :arrow Adds `dropdown-menu-arrow` to the menu, alongside
      #   any alignment class.
      # @option options [String] :align_breakpoint Responsive breakpoint (sm/md/lg/xl/xxl)
      #   -- combined with :align to add `dropdown-menu-<bp>-<align>` alongside the base
      #   alignment class. Validated via TablerUi::Breakpoint.
      # @option options [Hash] :html         HTML attributes for the outer wrapper (part :root)
      # @option options [Hash] :toggle_html  HTML attributes for the toggle button (part :toggle)
      # @option options [Hash] :menu_html    HTML attributes for the `.dropdown-menu` (part :menu)
      def initialize(options = {})
        @label = options[:label]
        @color = TablerUi::Color.validate!(options[:color], context: "dropdown") || "primary"
        @align = TablerUi::Align.validate!(options[:align], context: "dropdown")
        @direction = validate_direction!(options[:direction])
        @dark = options[:dark]
        @scrollable = options[:scrollable]
        @arrow = options[:arrow]
        @align_breakpoint = TablerUi::Breakpoint.validate!(options[:align_breakpoint], context: "dropdown")
        @items = []

        initialize_html_options(options)
      end

      # Adds a menu item.
      #
      # @param title [String] Item text
      # @param options [Hash]
      # @option options [String] :url Item URL (default: "#")
      # @option options [Symbol] :method HTTP method -- renders a button_to instead of a link when not :get
      # @option options [Boolean] :active
      # @option options [Boolean] :disabled
      # @option options [String] :icon Optional Tabler icon name, rendered via tabler_ui.icon
      # @option options [Hash, #call] :html HTML attributes for this item's
      #   link/button (part :item) -- a plain Hash, or a callable taking the item
      # @return [String] empty string, to avoid stray output in a capture context
      def item(title, options = {})
        builder_argument!(title, :title, builder: :item)

        @items << Item.new(
          type: :item,
          title: title,
          url: options.fetch(:url, "#"),
          method: options[:method],
          active: options[:active],
          disabled: options[:disabled],
          icon: options[:icon],
          html: options[:html]
        )

        ""
      end

      # Adds a divider.
      # @return [String] empty string, to avoid stray output in a capture context
      def divider
        @items << Item.new(type: :divider)
        ""
      end

      # Adds a header.
      # @param title [String] Header text
      # @return [String] empty string, to avoid stray output in a capture context
      def header(title)
        builder_argument!(title, :title, builder: :header)

        @items << Item.new(type: :header, title: title)
        ""
      end

      # @return [Hash] attributes for the outer wrapper (part :root)
      def root_attributes
        html_for(:root, class: DIRECTIONS.fetch(direction))
      end

      # @return [Hash] attributes for the toggle button (part :toggle)
      def toggle_attributes
        html_for(:toggle, class: "btn btn-#{color} dropdown-toggle")
      end

      # @return [Hash] attributes for the `.dropdown-menu` (part :menu)
      def menu_attributes
        html_for(:menu, class: menu_classes)
      end

      # @param item [Item] the item being rendered
      # @return [Hash] attributes for this item's link/button (part :item).
      #   Items repeat, so unlike the component-level hooks this resolves per
      #   item: the item's own :html (Hash or Proc taking the item) is loaded
      #   into the shared html_for storage just before resolving, then handed
      #   to html_for as normal.
      def item_attributes(item)
        @tabler_ui_html_options[:item] = item.html
        html_for(:item, { class: item_classes(item) }, item)
      end

      private

      def menu_classes
        classes = ["dropdown-menu"]
        classes << "dropdown-menu-end" if align == :end
        classes << "dropdown-menu-#{align_breakpoint}-#{align}" if align_breakpoint
        classes << "dropdown-menu-dark" if dark
        classes << "dropdown-menu-scrollable" if scrollable
        classes << "dropdown-menu-arrow" if arrow
        classes.join(" ")
      end

      def item_classes(item)
        classes = ["dropdown-item"]
        classes << "active" if item.active
        classes << "disabled" if item.disabled
        classes.join(" ")
      end

      # Returns the direction as a String key into DIRECTIONS, or raises
      # ArgumentError naming the offender and listing the valid values, in the
      # style of TablerUi::Color.validate! / TablerUi::Align.validate!.
      def validate_direction!(value)
        return "down" if value.nil?

        value = value.to_s
        return value if DIRECTIONS.key?(value)

        raise ArgumentError,
              "unknown direction #{value.inspect} for dropdown — valid: #{DIRECTIONS.keys.join(', ')}"
      end
    end
  end
end
