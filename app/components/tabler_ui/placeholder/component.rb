# frozen_string_literal: true

module TablerUi
  module Placeholder
    # Placeholder component for Tabler UI
    # Displays skeleton loading states for content
    #
    # @example Basic text placeholder
    #   <%= tabler_ui.placeholder type: :text, width: 9 %>
    #
    # @example Multiple text lines
    #   <%= tabler_ui.placeholder type: :text, lines: [10, 11, 8] %>
    #
    # @example Avatar placeholder
    #   <%= tabler_ui.placeholder type: :avatar %>
    #
    # @example Image placeholder
    #   <%= tabler_ui.placeholder type: :image, ratio: "21x9" %>
    #
    # @example Button placeholder
    #   <%= tabler_ui.placeholder type: :button, width: 4, color: "primary" %>
    #
    # @example Card placeholder with glow animation
    #   <%= tabler_ui.placeholder type: :card, animation: :glow %>
    #
    # @example HTML attributes -- the card's outer wrapper vs. its inner body
    #   <%= tabler_ui.placeholder type: :card, html: { class: "mb-3" }, body_html: { class: "p-4" } %>
    class Component
      include TablerUi::Base

      SIZES = %w[xs sm lg].freeze
      ANIMATIONS = %i[glow wave].freeze
      TYPES = %i[text avatar image button card list].freeze
      RATIOS = %w[1x1 4x3 16x9 21x9].freeze

      attr_reader :type, :width, :size, :animation, :ratio, :color, :lines,
                  :rounded, :show_image, :show_button

      # @param options [Hash]
      # @option options [Symbol]  :type        Placeholder type (:text, :avatar, :image, :button, :card, :list) (default: :text)
      # @option options [Integer] :width       Column width for text/button placeholders (1-12)
      # @option options [String]  :size        Size variant (xs, sm, lg) for the :text/fallback
      #   placeholder (raises ArgumentError if unrecognized). Not validated for the :avatar
      #   type, which uses its own, larger .avatar-* size scale.
      # @option options [Symbol]  :animation   Animation type (:glow, :wave)
      # @option options [String]  :ratio       Aspect ratio for images (1x1, 4x3, 16x9, 21x9)
      # @option options [String]  :color       Tabler color name, validated via TablerUi::Color and
      #   rendered as "btn-<color>" on the :button type
      # @option options [Array<Integer>] :lines Column widths for multiple text lines
      # @option options [Boolean] :rounded     Whether the :avatar placeholder is rounded (default: true)
      # @option options [Boolean] :show_image  Show the image block in the :card placeholder (default: true)
      # @option options [Boolean] :show_button Show the button block in the :card placeholder (default: true)
      # @option options [Hash]    :html        HTML attributes for the active type's own root element
      # @option options [Hash]    :body_html   HTML attributes for the :card type's inner .card-body
      def initialize(options = {})
        @type = (options[:type] || :text).to_sym
        @width = options[:width]
        @size = options[:size]
        @animation = options[:animation]&.to_sym
        @ratio = options[:ratio]
        @color = TablerUi::Color.validate!(options[:color], context: "placeholder")
        @lines = options[:lines]
        @rounded = options.fetch(:rounded, true)
        @show_image = options.fetch(:show_image, true)
        @show_button = options.fetch(:show_button, true)

        validate_size!

        initialize_html_options(options)
      end

      # --- HTML attributes ------------------------------------------------
      #
      # One method per root/part the template renders. Each is the single
      # place that calls html_for for its element -- see #placeholder_classes
      # / #wrapper_classes / #avatar_classes / #button_classes below, none of
      # which touch the caller's html: hook.

      # @return [Hash] attributes for the :text type's root wrapper <div>.
      #   Always a wrapper (even without an animation) so :text has a stable
      #   element to hang the html: hook on.
      def text_wrapper_attributes
        html_for(:root, class: wrapper_classes)
      end

      # @return [Hash] attributes for the :avatar type's root <div>.
      def avatar_attributes
        html_for(:root, class: avatar_classes)
      end

      # @return [Hash] attributes for the :image type's root <div>.
      def image_attributes
        html_for(:root, class: "ratio #{ratio_class} placeholder")
      end

      # @return [Hash] attributes for the :button type's root <a>.
      def button_attributes
        html_for(:root, href: "#", tabindex: "-1", "aria-hidden": "true", class: button_classes)
      end

      # @return [Hash] attributes for the :card type's root <div>.
      def card_attributes
        html_for(:root, class: [card_classes, wrapper_classes].reject(&:blank?).join(" "))
      end

      # @return [Hash] attributes for the :card type's inner .card-body <div>
      #   -- a genuinely distinct structural part from the card's own wrapper.
      def card_body_attributes
        html_for(:body, class: "card-body")
      end

      # @return [Hash] attributes for the :list type's root <div>.
      def list_attributes
        html_for(:root, class: wrapper_classes)
      end

      # @return [Hash] attributes for the fallback root element rendered for
      #   any +type+ outside TYPES.
      def default_attributes
        html_for(:root, class: placeholder_classes)
      end

      # --- helpers used directly by the template --------------------------

      # @return [String] classes for a single text placeholder line. Repeated
      #   sibling lines aren't a distinct named part (there's no fixed count
      #   of them), so they're not individually hookable -- only the :text
      #   wrapper is.
      def text_line_classes(line_width)
        classes = ["placeholder"]
        classes << (size ? "placeholder-#{size}" : "placeholder-xs")
        classes << "col-#{line_width}"
        classes.join(" ")
      end

      # @return [String] image ratio class.
      def ratio_class
        return "ratio-#{ratio}" if ratio && RATIOS.include?(ratio)
        "ratio-21x9"
      end

      # @return [Boolean] whether an animation modifier is active.
      def has_animation?
        !animation.nil? && ANIMATIONS.include?(animation)
      end

      # @return [Array<Integer>] column widths for multiple text lines.
      def text_lines
        return lines if lines.is_a?(Array)
        return [width || 9] if width
        [9]
      end

      private

      # --- plain CSS class strings ----------------------------------------
      #
      # These don't know anything about the caller's html: hook. They just
      # compute the component's own base classes; the *_attributes methods
      # above are what merge them through html_for.

      def placeholder_classes
        classes = ["placeholder"]
        classes << "placeholder-#{size}" if size
        classes << "col-#{width}" if width
        classes.join(" ")
      end

      # Validated eagerly, like :color, so an unrecognized value raises before
      # rendering rather than being silently dropped by the SIZES gate that
      # used to live in #text_line_classes / #placeholder_classes. Skipped for
      # :avatar, which has its own, larger .avatar-* size scale (xxs..2xl) --
      # see #avatar_classes, which reads +size+ straight through unvalidated.
      #
      # @raise [ArgumentError] if +size+ is present, the type isn't :avatar,
      #   and the value isn't one of SIZES.
      def validate_size!
        return if size.nil? || type == :avatar
        return if SIZES.include?(size.to_s)

        raise ArgumentError,
              "unknown placeholder size #{size.inspect} -- valid: #{SIZES.join(', ')}"
      end

      def wrapper_classes
        has_animation? ? "placeholder-#{animation}" : ""
      end

      def avatar_classes
        classes = ["avatar", "placeholder"]
        classes << "avatar-rounded" if rounded
        classes << "avatar-#{size}" if size
        classes.join(" ")
      end

      def button_classes
        classes = ["btn", "disabled", "placeholder"]
        classes << "btn-#{color}" if color
        classes << "col-#{width}" if width
        classes.join(" ")
      end

      def card_classes
        "card"
      end
    end
  end
end
