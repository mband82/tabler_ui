# frozen_string_literal: true

module TablerUi
  module Status
    # Status component for Tabler UI. Displays status indicators with various
    # styles and colors: plain text badge, a dot in front of text, a
    # standalone dot with no text, or the 3-circle "status indicator" style.
    #
    # @example Basic status
    #   <%= tabler_ui.status text: "Active", color: "green" %>
    #
    # @example Status with dot
    #   <%= tabler_ui.status text: "Online", color: "green", dot: true %>
    #
    # @example Animated status dot
    #   <%= tabler_ui.status text: "Processing", color: "blue", dot: true, animated: true %>
    #
    # @example Light variant
    #   <%= tabler_ui.status text: "Pending", color: "yellow", light: true %>
    #
    # @example Standalone dot
    #   <%= tabler_ui.status color: "green", dot: true, standalone: true %>
    #
    # @example Status indicator
    #   <%= tabler_ui.status color: "red", indicator: true %>
    #
    # @example Animated status indicator
    #   <%= tabler_ui.status color: "blue", indicator: true, animated: true %>
    #
    # @example HTML attributes on the root <span> and the inner dot <span>
    #   <%= tabler_ui.status text: "Online", dot: true,
    #                        html: { class: "me-2" }, dot_html: { data: { testid: "status-dot" } } %>
    class Component
      include TablerUi::Base

      # @param options [Hash]
      # @option options [String]  :text      Status text (optional for standalone dots/indicators)
      # @option options [String]  :color     Color variant, see TablerUi::Color::ALL (default: "blue")
      # @option options [Boolean] :dot       Show status dot in front of the text
      # @option options [Boolean] :animated  Animate the dot or indicator
      # @option options [Boolean] :light     Use the light/subtle variant (renders "status-lite")
      # @option options [Boolean] :standalone Render as a standalone dot (no text)
      # @option options [Boolean] :indicator Use the status indicator style (3 circles)
      # @option options [Hash]    :html      HTML attributes for the root <span> (part :root)
      # @option options [Hash]    :dot_html  HTML attributes for the inner dot <span> (part :dot),
      #   only rendered when a dot is shown alongside text (dot: true, standalone/indicator both false)
      def initialize(options = {})
        @text = options[:text]
        @color = TablerUi::Color.validate!(options[:color], context: "status") || "blue"
        @dot = options[:dot]
        @animated = options[:animated]
        @light = options[:light]
        @standalone = options[:standalone]
        @indicator = options[:indicator]

        initialize_html_options(options)
      end

      # @return [String, nil] the status text
      attr_reader :text

      # @return [Boolean] whether there is text to render
      def has_text?
        @text.present?
      end

      # @return [Boolean] whether the standalone dot / indicator should animate
      def animated?
        @animated
      end

      # @return [Boolean] whether this is a regular status with a dot in front of the text
      def with_dot?
        @dot && !@standalone && !@indicator
      end

      # @return [Boolean] whether to render as a standalone dot (no text)
      def standalone?
        @standalone
      end

      # @return [Boolean] whether to render as a 3-circle status indicator
      def indicator?
        @indicator
      end

      # @return [Hash] attributes for the root <span> (part :root), merged
      #   with whatever the caller supplied via html:.
      def root_attributes
        html_for(:root, class: root_classes)
      end

      # @return [Hash] attributes for the inner dot <span> (part :dot), merged
      #   with whatever the caller supplied via dot_html:. Only relevant when
      #   with_dot? is true.
      def dot_attributes
        html_for(:dot, class: dot_classes)
      end

      private

      def root_classes
        classes = []

        if @indicator
          classes << "status-indicator"
          classes << "status-indicator-animated" if @animated
          classes << "status-#{@color}"
        elsif @standalone
          classes << "status-dot"
          classes << "status-dot-animated" if @animated
          classes << "status-#{@color}"
        else
          classes << "status"
          classes << "status-#{@color}"
          classes << "status-lite" if @light
        end

        classes.join(" ")
      end

      def dot_classes
        classes = ["status-dot"]
        classes << "status-dot-animated" if @animated
        classes.join(" ")
      end
    end
  end
end
