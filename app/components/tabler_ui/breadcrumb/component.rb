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
    # @example HTML attributes -- root and per-item
    #   <%= tabler_ui.breadcrumb(html: { class: "mb-3" }) do |breadcrumb| %>
    #     <% breadcrumb.item("Home", url: "/", html: { class: "fw-bold" }) %>
    #     <% breadcrumb.item("Library", url: "/library",
    #                         html: ->(item) { { class: "text-danger" } if item.title == "Library" }) %>
    #   <% end %>
    #
    # @example link_html: -- HTML attributes on the `<a>` element itself (linked items only)
    #   <%= tabler_ui.breadcrumb(link_html: { class: "fw-bold" }) do |breadcrumb| %>
    #     <% breadcrumb.item("Home", url: "/") %>
    #     <% breadcrumb.item("Data") %>
    #   <% end %>
    #
    # ## Accessibility
    #
    # The `<ol class="breadcrumb">` sits inside a `<nav>` landmark with a
    # translated `aria-label`. The current item (see `#current?`) renders as
    # plain text, not a link, with the `active` class and `aria-current="page"`:
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
    # If no item is marked `active: true`, the *last* item added is treated
    # as current automatically -- no link, `active` class, `aria-current="page"`
    # -- even if it has a `url:`. As soon as any item is given `active: true`,
    # the automatic last-item behaviour turns off entirely: only the
    # explicitly marked item(s) are current, and every other item, including
    # the last, renders normally based on its own `url:`.
    #
    # ## The `link_html:` hook and non-linked items
    #
    # `link_html:` only reaches the `<a>` element. An item with no `url:`, or
    # the current item (which never links, even with a `url:`), renders as
    # bare text with no `<a>` to apply it to -- `link_html:` is silently
    # skipped in that case. Target the `<li>` instead via the item's own
    # `html:` (part :item) when you need to reach a non-linked item.
    class Component
      include TablerUi::Base
      builder_style!

      STYLES = %i[dots arrows bullets].freeze

      # :html holds the caller's *raw* per-item hook (Hash or Proc taking the
      # item), not resolved attributes -- see #item_attributes.
      # :auth holds the item's *effective* auth: value -- its own if it gave
      # one, otherwise the breadcrumb's own (CLAUDE.md rule 8's inheritance
      # rule) -- already resolved by the time the Item exists. It's not read
      # anywhere yet, but kept for parity with the other builder-style
      # components and any future need to introspect an item's auth: value.
      Item = Struct.new(:title, :url, :active, :html, :auth, keyword_init: true)

      attr_reader :style, :muted, :items, :aria_label

      # @param options [Hash]
      # @option options [Symbol, String] :style One of `:dots`, `:arrows`,
      #   `:bullets` -- selects the divider glyph. `nil` (the default) renders
      #   the plain "/" divider. Anything else raises `ArgumentError`.
      # @option options [Boolean] :muted Renders links in a muted (secondary)
      #   colour via `breadcrumb-muted`.
      # @option options [Hash] :html HTML attributes for the `<ol class="breadcrumb">` (part :root)
      # @option options [Hash, #call] :link_html HTML attributes for every
      #   item's `<a>` (part :link) -- a Hash, or a callable taking the item.
      #   Only applied when the item renders as a link -- see "The
      #   `link_html:` hook and non-linked items" above.
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
      # @option options [Hash, #call] :html HTML attributes for this item's
      #   `<li class="breadcrumb-item">` (part :item) -- a plain Hash, or a
      #   callable taking the item
      # @option options :auth Per-item authorization check (CLAUDE.md rule 8),
      #   run through the globally configured auth_method. Defaults to the
      #   breadcrumb's own `auth:` value when omitted -- so an unauthorized
      #   breadcrumb's items are unauthorized by default too, unless an item
      #   overrides it with its own `auth:`. A denied item is silently never
      #   added -- it does not appear in #items and never renders.
      # @return [String] empty string, to avoid stray output in a capture context
      def item(title, options = {})
        effective_auth = options.key?(:auth) ? options[:auth] : auth
        return "" unless TablerUi::Authorization.authorized?(effective_auth)

        builder_argument!(title, :title, builder: :item)

        @items << Item.new(
          title: title,
          url: options[:url],
          active: options[:active],
          html: options[:html],
          auth: effective_auth
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

      # @param item [Item] the item being rendered -- only called when
      #   #link?(item) is true, so item.url is guaranteed present
      # @return [Hash] attributes for this item's `<a>` (part :link),
      #   merging the component-level `link_html:` hook (a Hash applied to
      #   every linked item, or a callable taking the item -- the
      #   `pagination#link_html:`/`table#row_html:` pattern) over the base
      #   `href:`. Not called for non-linked items -- see "The `<a>` hook and
      #   the non-linked case" in the class docs.
      def link_attributes(item)
        html_for(:link, { href: item.url }, item)
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
