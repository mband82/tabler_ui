# frozen_string_literal: true

module TablerUi
  module Badge
    # Badge component for Tabler UI
    # Displays small count and labeling components
    #
    # @example Basic badge
    #   <%= tabler_ui.badge text: "New", color: "blue" %>
    #
    # @example Light variant
    #   <%= tabler_ui.badge text: "Pending", color: "yellow", light: true %>
    #
    # @example Pill badge
    #   <%= tabler_ui.badge text: "4", color: "red", pill: true %>
    #
    # @example Notification dot (no mandatory argument at all)
    #   <%= tabler_ui.badge color: "red", notification: true %>
    #
    # @example Blinking notification
    #   <%= tabler_ui.badge color: "red", notification: true, blink: true %>
    #
    # @example Outline variant
    #   <%= tabler_ui.badge text: "Draft", color: "secondary", outline: true %>
    #
    # @example With icon
    #   <%= tabler_ui.badge text: "Star", color: "yellow", icon: "star" %>
    #
    # @example As link
    #   <%= tabler_ui.badge text: "Click me", color: "blue", url: "/path" %>
    #
    # @example With size
    #   <%= tabler_ui.badge text: "Small", color: "green", size: :sm %>
    #   <%= tabler_ui.badge text: "Large", color: "green", size: :lg %>
    #
    # @example Rule 5 hook on the root <a>/<span>
    #   <%= tabler_ui.badge text: "New", html: { class: "me-2", data: { testid: "new-badge" } } %>
    class Component
      include TablerUi::Base

      SIZES = %w[sm lg].freeze

      attr_reader :text, :color, :light, :pill, :notification, :blink,
                  :outline, :icon, :url, :size, :content

      attr_writer :content

      # @param options [Hash]
      # @option options [String]  :text         Badge text
      # @option options [String]  :color        Color variant -- validated against
      #   TablerUi::Color (Tabler palette + Bootstrap semantic names)
      # @option options [Boolean] :light        Use light/subtle variant (default: false)
      # @option options [Boolean] :pill         Rounded pill shape (default: false)
      # @option options [Boolean] :notification Empty notification dot (default: false)
      # @option options [Boolean] :blink        Blinking animation for notification dots (default: false)
      # @option options [Boolean] :outline      Outline variant, i.e. "badge-outline" (default: false)
      # @option options [String]  :icon         Tabler icon name
      # @option options [String]  :url          URL to make the badge a link (renders <a> instead of <span>)
      # @option options [String, Symbol] :size  Badge size (:sm or :lg)
      # @option options [String, ActiveSupport::SafeBuffer] :content
      #   Block/caller-supplied body content. A plain String is escaped like
      #   any other <%= %> output; only a value that already arrived as an
      #   ActiveSupport::SafeBuffer is trusted verbatim.
      # @option options [Hash]    :html         Rule 5 HTML hook for the root <a>/<span> (part :root)
      def initialize(options = {})
        @text = options[:text]
        @color = TablerUi::Color.validate!(options[:color], context: "badge")
        @light = options[:light]
        @pill = options[:pill]
        @notification = options[:notification]
        @blink = options[:blink]
        @outline = options[:outline]
        @icon = options[:icon]
        @url = options[:url]
        @size = validate_size(options[:size])
        @content = options[:content]

        initialize_html_options(options)
      end

      # Whether to render as a link
      # @return [Boolean]
      def link?
        @url.present?
      end

      # Whether the badge has an icon
      # @return [Boolean]
      def has_icon?
        @icon.present?
      end

      # Whether the badge has visible text content
      # @return [Boolean]
      def has_text?
        @text.present?
      end

      # @return [Hash] attributes for the root <a>/<span> (part :root), merged
      #   with whatever the caller supplied via html:.
      def root_attributes
        defaults = { class: badge_classes }
        defaults[:href] = @url if link?

        html_for(:root, defaults)
      end

      private

      # CSS classes for the badge element
      # @return [String] Combined CSS classes
      def badge_classes
        classes = ["badge"]

        if @color
          suffix = @light ? "-lt" : ""
          classes << "bg-#{@color}#{suffix}"
          classes << "text-#{@color}#{suffix}-fg"
        end

        classes << "badge-pill" if @pill
        classes << "badge-notification" if @notification
        classes << "badge-blink" if @blink
        classes << "badge-outline" if @outline
        classes << "badge-#{@size}" if @size

        classes.join(" ")
      end

      def validate_size(size)
        return nil if size.nil?

        s = size.to_s
        SIZES.include?(s) ? s : nil
      end
    end
  end
end
