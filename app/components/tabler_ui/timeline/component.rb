# frozen_string_literal: true

module TablerUi
  module Timeline
    # Timeline component for Tabler UI. Renders a `ul.timeline` of dated /
    # ordered events, each an `li.timeline-event` with an icon box
    # (`.timeline-event-icon`) and a content card (`.timeline-event-card`).
    # Builder-style: the block yields the component itself, and events are
    # added via #item.
    #
    # @example Basic usage
    #   <%= tabler_ui.timeline do |t| %>
    #     <% t.item icon: "check" do %>
    #       <strong>Order placed</strong>
    #       <div class="text-secondary">2 hours ago</div>
    #     <% end %>
    #     <% t.item icon: "truck", color: "blue" do %>
    #       Shipped
    #     <% end %>
    #   <% end %>
    #
    # @example simple: -- hides the icon column entirely
    #   <%= tabler_ui.timeline simple: true do |t| %>
    #     <% t.item { "Signed up" } %>
    #   <% end %>
    #
    # @example An item's card content is entirely up to the caller -- nest a
    #   real card if you want one, the component does not bake card structure in
    #   <% t.item icon: "star" do %>
    #     <%= tabler_ui.card title: "Milestone" do |slots| %>
    #       <% slots.body { "5 years!" } %>
    #     <% end %>
    #   <% end %>
    #
    # @example HTML attributes -- component-level and per-item
    #   <%= tabler_ui.timeline html: { class: "mb-4" },
    #                          item_html: ->(item) { { class: "fw-bold" } if item.color == "red" } do |t| %>
    #     <% t.item icon: "flag", color: "red", icon_html: { class: "border" },
    #               card_html: { class: "p-2" } do %>
    #       Flagged
    #     <% end %>
    #   <% end %>
    class Component
      include TablerUi::Base
      builder_style!

      # :icon_html / :card_html hold the caller's *raw* per-item hook (Hash or
      # Proc taking the item), not resolved attributes -- see #icon_attributes
      # / #card_attributes, which mirror Tabs#tab_attributes.
      Item = Struct.new(:icon, :color, :icon_html, :card_html, :content, keyword_init: true)

      attr_reader :items, :simple

      # @param options [Hash]
      # @option options [Boolean] :simple Hides the icon column entirely and drops the
      #   card's left margin (`timeline-simple`, default: false).
      # @option options [Hash]       :html      HTML attributes for the outer `ul.timeline` (part :root)
      # @option options [Hash, Proc] :item_html HTML attributes for each `li.timeline-event` (part :item).
      #   Either a plain Hash (applied to every item) or a callable taking the
      #   item and returning a Hash.
      def initialize(options = {})
        @simple = options[:simple]
        @items = []

        initialize_html_options(options)
      end

      # Adds an event to the timeline. No mandatory argument -- unlike, say,
      # Breadcrumb#item(title), a timeline event has no single obvious
      # mandatory string; its content comes entirely from the block. So
      # `builder_argument!` does not apply here.
      #
      # @param options [Hash]
      # @option options [String] :icon Optional Tabler icon name for the
      #   `.timeline-event-icon` box, rendered via the tabler_ui.icon
      #   dispatcher (never by instantiating TablerUi::Icon::Component
      #   directly -- that coupling has broken twice already). An item with
      #   no icon still renders the (empty) icon box, so spacing and the
      #   timeline connector line stay consistent and `icon_html:` always has
      #   a real target to hook onto.
      # @option options [String] :color Colour for the icon box -- validated
      #   against TablerUi::Color. `.timeline-event-icon` has no colour
      #   modifier classes of its own in the CSS (unlike `steps-*`/`toast-*`),
      #   so this is translated into "bg-<color>-lt" on the box, with the
      #   same `color:` forwarded to `tabler_ui.icon` for the glyph itself --
      #   the same "-lt box + coloured icon" pairing StatCard's icon box
      #   already uses, reused rather than inventing a new convention.
      # @option options [Hash, #call] :icon_html HTML attributes for this
      #   item's `.timeline-event-icon` (part :icon) -- a plain Hash, or a
      #   callable taking the item
      # @option options [Hash, #call] :card_html HTML attributes for this
      #   item's `.timeline-event-card` (part :card) -- a plain Hash, or a
      #   callable taking the item
      # @param block [Proc] Event content, captured at render time and
      #   rendered as-is inside `.timeline-event-card`. Deliberately left
      #   unstructured -- `.timeline-event-card` is generic in the CSS
      #   (nothing enforces a `.card` inside it), so a caller who wants a
      #   card nests `tabler_ui.card` themselves rather than this component
      #   baking card structure in.
      # @return [String] empty string, to avoid stray output in a capture context
      def item(options = {}, &block)
        @items << Item.new(
          icon: options[:icon],
          color: TablerUi::Color.validate!(options[:color], context: "timeline"),
          icon_html: options[:icon_html],
          card_html: options[:card_html],
          content: block
        )

        ""
      end

      # @return [Boolean] whether there are any events to render
      def any?
        @items.any?
      end

      # @param item [Item] the current item being rendered
      # @return [Boolean] whether this item has an icon to render
      def icon?(item)
        item.icon.present?
      end

      # @return [Hash] attributes for the outer `ul.timeline` (part :root)
      def root_attributes
        html_for(:root, class: root_classes)
      end

      # @param item [Item] the current item being rendered
      # @return [Hash] attributes for this item's `li.timeline-event` (part :item)
      def item_attributes(item)
        html_for(:item, { class: "timeline-event" }, item)
      end

      # @param item [Item] the current item being rendered
      # @return [Hash] attributes for this item's icon box (part :icon).
      #   Unlike :root/:item, this hook lives on the item itself (set via
      #   `item(icon_html: ...)`), so it's loaded into the shared html_for
      #   storage just before resolving -- see Tabs#tab_attributes for the
      #   same mechanism.
      def icon_attributes(item)
        @tabler_ui_html_options[:icon] = item.icon_html
        html_for(:icon, { class: icon_classes(item) }, item)
      end

      # @param item [Item] the current item being rendered
      # @return [Hash] attributes for this item's content card (part :card).
      #   Same per-item mechanism as #icon_attributes.
      def card_attributes(item)
        @tabler_ui_html_options[:card] = item.card_html
        html_for(:card, { class: "timeline-event-card" }, item)
      end

      private

      def root_classes
        classes = ["timeline"]
        classes << "timeline-simple" if @simple
        classes.join(" ")
      end

      def icon_classes(item)
        classes = ["timeline-event-icon"]
        classes << "bg-#{item.color}-lt" if item.color
        classes.join(" ")
      end
    end
  end
end
