# frozen_string_literal: true

module TablerUi
  module Breadcrumb
    # Breadcrumb navigation component for Tabler UI. Builder-style: the block
    # yields the component itself, and entries are added via #item.
    #
    # @example Basic usage
    #   <%= tabler_ui.breadcrumb do |breadcrumb| %>
    #     <% breadcrumb.item("Home", url: "/") %>
    #     <% breadcrumb.item("Library", url: "/library") %>
    #     <% breadcrumb.item("Data") %>
    #   <% end %>
    #
    # @example Divider style and muted links
    #   <%= tabler_ui.breadcrumb(style: :arrows, muted: true) do |breadcrumb| %>
    #     ...
    #   <% end %>
    #
    # @example Explicit current item (overrides the last-item default)
    #   <%= tabler_ui.breadcrumb do |breadcrumb| %>
    #     <% breadcrumb.item("Home", url: "/") %>
    #     <% breadcrumb.item("Reports", url: "/reports", active: true) %>
    #     <% breadcrumb.item("2024", url: "/reports/2024") %>
    #   <% end %>
    #
    # @example Rule 5 hooks -- root and per-item
    #   <%= tabler_ui.breadcrumb(html: { class: "mb-3" }) do |breadcrumb| %>
    #     <% breadcrumb.item("Home", url: "/", html: { class: "fw-bold" }) %>
    #     <% breadcrumb.item("Library", url: "/library",
    #                         html: ->(item) { { class: "text-danger" } if item.title == "Library" }) %>
    #   <% end %>
    #
    # ## Accessibility
    #
    # The `<ol class="breadcrumb">` is wrapped in a `<nav>` landmark with a
    # translated `aria-label` (see config/locales/en.yml,
    # tabler_ui.breadcrumb.aria_label), matching the standard breadcrumb
    # pattern. Whichever item is "current" (see #current? below) renders as
    # plain text rather than a link, carries the `active` class, and gets
    # `aria-current="page"` -- mirroring Bootstrap's own reference markup:
    #
    #   <nav aria-label="breadcrumb">
    #     <ol class="breadcrumb">
    #       <li class="breadcrumb-item"><a href="#">Home</a></li>
    #       <li class="breadcrumb-item active" aria-current="page">Data</li>
    #     </ol>
    #   </nav>
    #
    # ## Current item resolution
    #
    # Breadcrumbs almost always end at the current page, so when no item is
    # explicitly marked `active: true`, the *last* item added is treated as
    # current automatically -- no link, `active` class, `aria-current="page"`
    # -- even if it was given a `url:`. This matches how breadcrumbs are used
    # in practice (the trailing crumb is the page you're on, and callers
    # rarely bother passing `active: true` on it explicitly).
    #
    # As soon as any item is given `active: true` explicitly, the automatic
    # last-item behaviour is switched off entirely: only the explicitly
    # marked item(s) are current, and every other item -- including the last
    # one -- renders as a normal link/text node based on its own `url:`.
    # This keeps the rule explicit rather than magical: either you opt in to
    # marking the current item yourself, or the component makes the one
    # obvious default choice for you.
    class Component
      include TablerUi::Base
      builder_style!

      STYLES = %i[dots arrows bullets].freeze

      # :html holds the caller's *raw* per-item hook (Hash or Proc taking the
      # item), not resolved attributes -- see #item_attributes.
      Item = Struct.new(:title, :url, :active, :html, keyword_init: true)

      attr_reader :style, :muted, :items, :aria_label

      # @param options [Hash]
      # @option options [Symbol, String] :style One of :dots, :arrows, :bullets --
      #   selects the `--tblr-breadcrumb-divider` glyph via a class on the
      #   `<ol>`. nil (the default) renders the plain "/" divider. Anything
      #   else raises ArgumentError naming the component and the valid values.
      # @option options [Boolean] :muted Renders links in a muted (secondary) colour
      #   via `breadcrumb-muted`.
      # @option options [Hash] :html Rule 5 HTML hook for the `<ol class="breadcrumb">` (part :root)
      def initialize(options = {})
        @style = validate_style(options[:style])
        @muted = options[:muted]
        @items = []
        @aria_label = I18n.t("tabler_ui.breadcrumb.aria_label")

        initialize_html_options(options)
      end

      # Adds a breadcrumb entry.
      #
      # @param title [String] Item text
      # @param options [Hash]
      # @option options [String] :url Item URL. When absent, the item renders
      #   as plain text instead of a link. Ignored for the current item (see
      #   #current? -- the current item never renders as a link).
      # @option options [Boolean] :active Marks this item as the current page.
      #   See the class docs above for how this interacts with the automatic
      #   last-item default.
      # @option options [Hash, #call] :html Rule 5 HTML hook for this item's
      #   `<li class="breadcrumb-item">` (part :item) -- a plain Hash, or a
      #   callable taking the item
      # @return [String] empty string, to avoid stray output in a capture context
      def item(title, options = {})
        builder_argument!(title, :title, builder: :item)

        @items << Item.new(
          title: title,
          url: options[:url],
          active: options[:active],
          html: options[:html]
        )

        ""
      end

      # @return [Hash] attributes for the `<ol class="breadcrumb">` (part :root)
      def root_attributes
        html_for(:root, class: list_classes)
      end

      # @param item [Item] the item being rendered
      # @return [Hash] attributes for this item's `<li>` (part :item). Items
      #   repeat, so unlike the component-level hook this resolves per item:
      #   the item's own :html (Hash or Proc taking the item) is loaded into
      #   the shared html_for storage just before resolving, then handed to
      #   html_for as normal.
      def item_attributes(item)
        @tabler_ui_html_options[:item] = item.html

        defaults = { class: item_classes(item) }
        defaults[:"aria-current"] = "page" if current?(item)

        html_for(:item, defaults, item)
      end

      # @param item [Item] the item being tested
      # @return [Boolean] whether this item renders as a link. The current
      #   item never links, even if it was given a url:.
      def link?(item)
        item.url.present? && !current?(item)
      end

      # @param item [Item] the item being tested
      # @return [Boolean] whether this item is the current page -- see the
      #   class docs' "Current item resolution" section.
      def current?(item)
        return !!item.active if any_explicit_active?

        item.equal?(items.last)
      end

      private

      def any_explicit_active?
        items.any?(&:active)
      end

      def list_classes
        classes = ["breadcrumb"]
        classes << "breadcrumb-#{style}" if style
        classes << "breadcrumb-muted" if muted
        classes.join(" ")
      end

      def item_classes(item)
        classes = ["breadcrumb-item"]
        classes << "active" if current?(item)
        classes.join(" ")
      end

      def validate_style(value)
        return nil if value.nil?

        style = value.to_sym
        return style if STYLES.include?(style)

        raise ArgumentError,
              "unknown breadcrumb style #{value.inspect} — valid: #{STYLES.join(', ')}"
      end
    end
  end
end
