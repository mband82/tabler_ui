# frozen_string_literal: true

module TablerUi
  module Carousel
    # Carousel component for Tabler UI. Renders Bootstrap's
    # `.carousel > .carousel-inner > .carousel-item` slideshow, plus optional
    # indicators and prev/next controls. Builder-style: the block yields the
    # component itself, and slides are added via #item.
    #
    # @example Basic usage -- images
    #   <%= tabler_ui.carousel("my-carousel") do |carousel| %>
    #     <% carousel.item(image: image_path("slide1.jpg")) %>
    #     <% carousel.item(image: image_path("slide2.jpg"), active: true) %>
    #     <% carousel.item(image: image_path("slide3.jpg")) %>
    #   <% end %>
    #
    # @example Custom slide content instead of image:
    #   <%= tabler_ui.carousel("my-carousel") do |carousel| %>
    #     <% carousel.item { render "some/partial" } %>
    #   <% end %>
    #
    # @example Captions, fade transition, no controls/indicators
    #   <%= tabler_ui.carousel("my-carousel", fade: true, controls: false, indicators: false) do |carousel| %>
    #     <% carousel.item(image: "a.jpg", caption: "First slide", caption_background: true) %>
    #   <% end %>
    #
    # @example Indicator variants and autoplay tuning
    #   <%= tabler_ui.carousel("my-carousel", indicators: :thumb, interval: 3000, wrap: false, keyboard: false) do |carousel| %>
    #     ...
    #   <% end %>
    #
    # @example Rule 5 hooks -- component-level and per-item
    #   <%= tabler_ui.carousel("my-carousel", html: { class: "mb-3" },
    #                          inner_html: { class: "rounded" },
    #                          indicators_html: { class: "mb-0" },
    #                          prev_html: { class: "text-dark" },
    #                          next_html: { class: "text-dark" }) do |carousel| %>
    #     <% carousel.item(image: "a.jpg", html: { class: "bg-dark" }, caption: "x", caption_html: { class: "fw-bold" }) %>
    #   <% end %>
    #
    # ## Which slide is active
    #
    # Unlike `steps` (a single `current:` index, because its CSS only makes
    # sense with one dimming boundary) this follows `tabs`' precedent: a
    # per-item `active:` flag, first-item-wins when nothing is marked --
    #
    #   is_active = options[:active].nil? ? @items.empty? : options[:active]
    #
    # -- so a lone slide, or the first of several with no explicit `active:`
    # anywhere, comes out active with zero ceremony. `tabs` stops there and
    # tolerates whatever the caller produces. Carousel cannot: Bootstrap's
    # `.active` selector picks the *first* match, so zero active items shows
    # a blank frame and several active items shows several stacked on top of
    # each other -- both silent. #validate! (called by the dispatcher once
    # the block has run, see `TablerUi::Ui#render_block`) enforces exactly
    # one, turning what would be a blank carousel into an ArgumentError at
    # render time.
    #
    # ## Autoplay
    #
    # The root always carries `data-bs-ride="carousel"` (Bootstrap's own
    # opt-in for "start cycling on page load", per its Carousel docs), so a
    # carousel autoplays with Bootstrap's 5000ms default unless tuned via
    # `interval:`. Pass `interval: false` to disable autoplay entirely while
    # keeping manual prev/next/indicator navigation -- Bootstrap's own
    # documented contract for that value.
    #
    # ## Accessibility
    #
    # The root carries `role="region"` / `aria-roledescription="carousel"` /
    # a translated `aria-label`, and each slide carries `role="group"` /
    # `aria-roledescription="slide"` / a translated "Slide N of M" label --
    # the WAI-ARIA carousel pattern Bootstrap's own docs point to. Indicator
    # buttons get a translated "Slide N" `aria-label` plus `aria-current`
    # on the active one; prev/next controls get translated visually-hidden
    # text, matching Bootstrap's own example markup.
    #
    # Note: the block yields the component itself (builder style) --
    # `do |carousel| carousel.item(...) end`, not a SlotContext.
    class Component
      include TablerUi::Base
      builder_style!

      # :html / :caption_html hold the caller's *raw* per-item hooks (Hash or
      # Proc taking the item), not resolved attributes -- see #item_attributes
      # / #caption_attributes. :index is 0-based, set by #item in call order.
      Item = Struct.new(:image, :caption, :caption_background, :active, :content, :html, :caption_html, :index,
                         keyword_init: true)

      INDICATOR_VARIANTS = %i[dot thumb vertical].freeze

      attr_reader :id, :items

      # @param id [String] Mandatory DOM id for the `.carousel` root --
      #   indicators and controls both target it via `data-bs-target="#id"`.
      # @param options [Hash]
      # @option options [Boolean] :fade Cross-fade between slides instead of
      #   sliding (`carousel-fade`, default: false)
      # @option options [Boolean, Symbol] :indicators Indicator dots below the
      #   slides -- `true` (default), `false`, or a variant: `:dot`, `:thumb`
      #   (renders each indicator as a background-image thumbnail from that
      #   slide's `image:`, when present), `:vertical`
      # @option options [Boolean] :controls Prev/next arrow buttons (default: true)
      # @option options [Integer, Boolean] :interval Milliseconds between
      #   automatic slides, or `false` to disable autoplay -- maps to
      #   `data-bs-interval`. Omitted entirely (Bootstrap's own 5000ms
      #   default applies) unless given explicitly.
      # @option options [Boolean] :wrap Whether the carousel cycles
      #   continuously (default: true) or hard-stops at the first/last slide --
      #   maps to `data-bs-wrap`. Omitted unless given explicitly.
      # @option options [Boolean] :keyboard Whether the carousel responds to
      #   arrow keys while focused (default: true) -- maps to `data-bs-keyboard`.
      #   Omitted unless given explicitly.
      # @option options [Hash] :html Rule 5 HTML hook for the root `.carousel` (part :root)
      # @option options [Hash] :inner_html Rule 5 HTML hook for the `.carousel-inner` (part :inner)
      # @option options [Hash] :indicators_html Rule 5 HTML hook for the `.carousel-indicators` (part :indicators)
      # @option options [Hash] :prev_html Rule 5 HTML hook for the prev control (part :prev)
      # @option options [Hash] :next_html Rule 5 HTML hook for the next control (part :next)
      def initialize(id, options = {})
        @id = id
        @fade = options[:fade]
        @indicators = validate_indicators!(options.fetch(:indicators, true))
        @controls = options.fetch(:controls, true)
        @interval = options[:interval]
        @interval_given = options.key?(:interval)
        @wrap = options[:wrap]
        @wrap_given = options.key?(:wrap)
        @keyboard = options[:keyboard]
        @keyboard_given = options.key?(:keyboard)
        @items = []

        initialize_html_options(options)
      end

      # Adds a slide.
      #
      # @param options [Hash]
      # @option options [String] :image Image URL/path, rendered as the
      #   slide's content -- ignored when a block is given.
      # @option options [String] :caption Caption text, rendered in a
      #   `.carousel-caption` under the slide content.
      # @option options [Boolean] :caption_background Adds a dark
      #   `.carousel-caption-background` gradient behind the caption text, for
      #   legibility over busy images.
      # @option options [Boolean] :active Whether this is the active/visible
      #   slide (first slide added is active by default unless a later slide
      #   is explicitly marked active: true -- see the class docs' "Which
      #   slide is active" section)
      # @option options [Hash, #call] :html Rule 5 HTML hook for this slide's
      #   `.carousel-item` (part :item) -- a plain Hash, or a callable taking the item
      # @option options [Hash, #call] :caption_html Rule 5 HTML hook for this
      #   slide's `.carousel-caption` (part :caption) -- a plain Hash, or a
      #   callable taking the item
      # @param block [Proc] Slide content, captured in the template --
      #   replaces :image entirely when given
      # @return [String] empty string, to avoid stray output in a capture context
      def item(options = {}, &block)
        is_active = options[:active].nil? ? @items.empty? : options[:active]

        @items << Item.new(
          image: options[:image],
          caption: options[:caption],
          caption_background: options[:caption_background],
          active: is_active,
          content: block,
          html: options[:html],
          caption_html: options[:caption_html],
          index: @items.length
        )

        ""
      end

      # @return [Boolean] whether there are any slides
      def any?
        @items.any?
      end

      # @return [Boolean] whether indicators are rendered at all
      def indicators?
        @indicators != false
      end

      # @return [Boolean] whether prev/next controls are rendered
      def controls?
        @controls
      end

      # Called by TablerUi::Ui once the builder block has run and every slide
      # is known (see `lib/tabler_ui/ui.rb#render_block`) -- exactly one slide
      # must be active, or Bootstrap renders a blank (zero active) or
      # visually broken (several active) carousel with no error of its own.
      # Raising here keeps it an ArgumentError instead of a silently blank
      # carousel in production.
      def validate!
        return if @items.empty?

        active_count = @items.count(&:active)
        return if active_count == 1

        raise ArgumentError,
              "carousel #{id.inspect} requires exactly one active slide, found #{active_count} -- " \
              "Bootstrap renders a blank carousel with zero, and a broken one with several"
      end

      # @return [Hash] attributes for the root `.carousel` element (part :root)
      def root_attributes
        data = { controller: "tabler-ui--carousel", bs_ride: "carousel" }
        data[:bs_interval] = @interval if @interval_given
        data[:bs_wrap] = @wrap if @wrap_given
        data[:bs_keyboard] = @keyboard if @keyboard_given

        html_for(:root, id: id, class: root_classes, role: "region",
                         "aria-roledescription": "carousel", "aria-label": label, data: data)
      end

      # @return [Hash] attributes for the `.carousel-inner` (part :inner)
      def inner_attributes
        html_for(:inner, class: "carousel-inner")
      end

      # @return [Hash] attributes for the `.carousel-indicators` (part :indicators)
      def indicators_attributes
        html_for(:indicators, class: indicators_classes)
      end

      # @return [Hash] attributes for the prev control (part :prev)
      def prev_attributes
        html_for(:prev, class: "carousel-control-prev", data: { bs_target: "##{id}", bs_slide: "prev" })
      end

      # @return [Hash] attributes for the next control (part :next)
      def next_attributes
        html_for(:next, class: "carousel-control-next", data: { bs_target: "##{id}", bs_slide: "next" })
      end

      # @param item [Item] the slide being rendered
      # @return [Hash] attributes for this slide's `.carousel-item` (part :item)
      def item_attributes(item)
        @tabler_ui_html_options[:item] = item.html
        html_for(:item, item_html_defaults(item), item)
      end

      # @param item [Item] the slide being rendered
      # @return [Hash] attributes for this slide's `.carousel-caption` (part :caption)
      def caption_attributes(item)
        @tabler_ui_html_options[:caption] = item.caption_html
        html_for(:caption, { class: caption_classes(item) }, item)
      end

      # @param item [Item] the slide being rendered
      # @return [String, nil] inline `background-image` style for this item's
      #   indicator button, used only by the :thumb variant -- nil otherwise
      #   (and nil when the slide has no image:, leaving a blank thumbnail
      #   rather than raising -- the :thumb variant is a styling choice, not
      #   a guarantee every slide has art to show)
      def indicator_style(item)
        return nil unless @indicators == :thumb && item.image.present?

        "background-image: url(#{item.image})"
      end

      # @return [String] translated aria-label for the root
      def label
        I18n.t("tabler_ui.carousel.label")
      end

      # @return [String] translated visually-hidden text for the prev control
      def previous_label
        I18n.t("tabler_ui.carousel.previous")
      end

      # @return [String] translated visually-hidden text for the next control
      def next_label
        I18n.t("tabler_ui.carousel.next")
      end

      # @param index [Integer] 0-based slide index
      # @return [String] translated aria-label for that slide's indicator button
      def indicator_label(index)
        I18n.t("tabler_ui.carousel.slide", number: index + 1)
      end

      # @param item [Item] the slide being rendered
      # @return [String] translated aria-label for that slide's `.carousel-item`
      def slide_label(item)
        I18n.t("tabler_ui.carousel.slide_of", number: item.index + 1, total: items.length)
      end

      private

      def validate_indicators!(value)
        return false unless value

        return true if value == true

        variant = value.to_s.to_sym
        return variant if INDICATOR_VARIANTS.include?(variant)

        raise ArgumentError,
              "unknown carousel indicators: #{value.inspect} -- valid: true, false, #{INDICATOR_VARIANTS.join(', ')}"
      end

      def root_classes
        classes = ["carousel", "slide"]
        classes << "carousel-fade" if @fade
        classes.join(" ")
      end

      def indicators_classes
        classes = ["carousel-indicators"]
        classes << "carousel-indicators-#{@indicators}" if @indicators.is_a?(Symbol)
        classes.join(" ")
      end

      def item_html_defaults(item)
        {
          class: item_classes(item),
          role: "group",
          "aria-roledescription": "slide",
          "aria-label": slide_label(item)
        }
      end

      def item_classes(item)
        classes = ["carousel-item"]
        classes << "active" if item.active
        classes.join(" ")
      end

      def caption_classes(item)
        classes = ["carousel-caption"]
        classes << "carousel-caption-background" if item.caption_background
        classes.join(" ")
      end
    end
  end
end
