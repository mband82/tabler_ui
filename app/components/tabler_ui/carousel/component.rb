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
    # @example HTML attributes -- component-level and per-item
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
    # Each slide takes its own `active:` flag. If none is marked active, the
    # first slide added becomes active. Exactly one slide must end up
    # active -- zero or several raises `ArgumentError` once the block finishes.
    #
    # ## Autoplay
    #
    # Autoplays by default (Bootstrap's 5000ms interval) unless tuned via
    # `interval:`. Pass `interval: false` to disable autoplay while keeping
    # manual prev/next/indicator navigation.
    #
    # ## Accessibility
    #
    # The root carries `role="region"`, `aria-roledescription="carousel"` and
    # a translated `aria-label`. Each slide carries `role="group"`,
    # `aria-roledescription="slide"` and a translated "Slide N of M" label.
    # Indicator buttons get a translated "Slide N" label plus `aria-current`
    # on the active one; prev/next controls get translated visually-hidden text.
    #
    # Note: the block yields the component itself (`do |carousel| ... end`), not a SlotContext.
    class Component
      include TablerUi::Base
      builder_style!

      # :html / :caption_html hold the caller's *raw* per-item hooks (Hash or
      # Proc taking the item), not resolved attributes -- see #item_attributes
      # / #caption_attributes. :index is 0-based, set by #item in call order,
      # after excluding unauthorized slides -- so authorized slides stay
      # densely indexed and #slide_label's "N of M" is consistent with what
      # actually renders. :auth is the slide's resolved (post-inheritance)
      # `auth:` value (CLAUDE.md rule 8) -- stored for completeness, though
      # only authorized slides ever make it into @items in the first place.
      Item = Struct.new(:image, :caption, :caption_background, :active, :content, :html, :caption_html, :index, :auth,
                         keyword_init: true)

      INDICATOR_VARIANTS = %i[dot thumb vertical].freeze

      attr_reader :id, :items

      # @param id [String] Mandatory DOM id for the `.carousel` root --
      #   indicators and controls both target it via `data-bs-target="#id"`.
      # @param options [Hash]
      # @option options [Boolean] :fade Cross-fade between slides instead of
      #   sliding (`carousel-fade`, default: false)
      # @option options [Boolean] :dark Dark-variant controls/indicators/caption
      #   for use over light backgrounds (`carousel-dark`, default: false)
      # @option options [Boolean, Symbol] :indicators Indicator dots below the
      #   slides -- `true` (default), `false`, or a variant: `:dot`, `:thumb`
      #   (renders each indicator as a background-image thumbnail from that
      #   slide's `image:`, when present), `:vertical`
      # @option options [Boolean] :controls Prev/next arrow buttons (default: true)
      # @option options [Integer, Boolean] :interval Milliseconds between
      #   automatic slides, or `false` to disable autoplay. Bootstrap's own
      #   5000ms default applies when omitted.
      # @option options [Boolean] :wrap Whether the carousel cycles
      #   continuously (default: true) or hard-stops at the first/last slide.
      # @option options [Boolean] :keyboard Whether the carousel responds to
      #   arrow keys while focused (default: true).
      # @option options [Hash] :html HTML attributes for the root `.carousel` (part :root)
      # @option options [Hash] :inner_html HTML attributes for the `.carousel-inner` (part :inner)
      # @option options [Hash] :indicators_html HTML attributes for the `.carousel-indicators` (part :indicators)
      # @option options [Hash] :prev_html HTML attributes for the prev control (part :prev)
      # @option options [Hash] :next_html HTML attributes for the next control (part :next)
      def initialize(id, options = {})
        @id = id
        @fade = options[:fade]
        @dark = options[:dark]
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
      # @option options [Hash, #call] :html HTML attributes for this slide's
      #   `.carousel-item` (part :item) -- a plain Hash, or a callable taking the item
      # @option options [Hash, #call] :caption_html HTML attributes for this
      #   slide's `.carousel-caption` (part :caption) -- a plain Hash, or a
      #   callable taking the item
      # @option options [Object] :auth Per-slide authorization value (CLAUDE.md
      #   rule 8) -- checked against the globally configured auth_method.
      #   Defaults to carousel's own :auth when omitted. An unauthorized slide
      #   is not appended, so it never factors into the first-slide-active
      #   default nor into #validate!'s exactly-one-active check -- :index is
      #   assigned from @items.length *after* exclusion, keeping authorized
      #   slides densely indexed (0, 1, 2, ...).
      # @param block [Proc] Slide content, captured in the template --
      #   replaces :image entirely when given
      # @return [String, nil] empty string, to avoid stray output in a
      #   capture context; nil (no-op) if :auth denied it
      def item(options = {}, &block)
        effective_auth = options.key?(:auth) ? options[:auth] : auth
        return unless TablerUi::Authorization.authorized?(effective_auth)

        is_active = options[:active].nil? ? @items.empty? : options[:active]

        @items << Item.new(
          image: options[:image],
          caption: options[:caption],
          caption_background: options[:caption_background],
          active: is_active,
          content: block,
          html: options[:html],
          caption_html: options[:caption_html],
          index: @items.length,
          auth: effective_auth
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
      #
      # Unlike `steps` (a single `current:` index, since its CSS only makes
      # sense with one dimming boundary), this follows `tabs`' precedent of a
      # per-item `active:` flag with first-item-wins when nothing is marked
      # (see #item's `is_active` line). `tabs` stops there and tolerates
      # whatever the caller produces; carousel can't, because Bootstrap's
      # `.active` selector picks the first match regardless of how many
      # elements carry the class, so this validation exists to turn that
      # silent failure mode into a loud one.
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
        classes << "carousel-dark" if @dark
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
