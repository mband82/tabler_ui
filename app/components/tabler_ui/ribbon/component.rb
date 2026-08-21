# frozen_string_literal: true

module TablerUi
  module Ribbon
    # Ribbon component for Tabler UI. A small label pinned to a corner of a
    # `position: relative` parent (typically a card) -- a single, absolutely
    # positioned element with no required inner structure.
    #
    # @example Basic usage -- default position (top) and side (end/right)
    #   <%= tabler_ui.ribbon text: "New", color: "blue" %>
    #
    # @example Bottom edge, start (left) side
    #   <%= tabler_ui.ribbon text: "Sale", color: "red", position: :bottom, align: :start %>
    #
    # @example Bookmark shape
    #   <%= tabler_ui.ribbon text: "Featured", color: "yellow", bookmark: true %>
    #
    # @example Bare coloured corner with an icon, no text
    #   <%= tabler_ui.ribbon icon: "star", color: "yellow" %>
    #
    # @example Rich content via a block -- wins over text: when both are given
    #   <%= tabler_ui.ribbon color: "green" do |slots| %>
    #     <% slots.body do %><strong>Hot</strong><% end %>
    #   <% end %>
    #
    # @example HTML attributes on the root element
    #   <%= tabler_ui.ribbon text: "New", html: { class: "me-2" } %>
    class Component
      include TablerUi::Base

      attr_reader :text, :color, :position, :align, :bookmark, :icon

      # @param options [Hash]
      # @option options [String] :text Ribbon label. Optional -- omit for a bare
      #   colour corner or an icon-only ribbon. A block, if given, overrides this.
      # @option options [String] :color Colour, validated against TablerUi::Color.
      #   Rendered as `bg-<color>`.
      # @option options [String, Symbol] :position Vertical edge: `:top` (default)
      #   or `:bottom`. Raises ArgumentError for anything else.
      # @option options [String, Symbol] :align Horizontal edge: `:start` or
      #   `:end` (default).
      # @option options [Boolean] :bookmark Bookmark shape (default: false)
      # @option options [String] :icon Tabler icon name
      # @option options [Hash] :html HTML attributes for the root element (part :root)
      def initialize(options = {})
        @text = options[:text]
        @color = TablerUi::Color.validate!(options[:color], context: "ribbon")
        @position = TablerUi::Position.validate!(options[:position], context: "ribbon",
                                                                       allowed: TablerUi::Position::VERTICAL)
        @align = options[:align].nil? ? :end : TablerUi::Align.validate!(options[:align], context: "ribbon")
        @bookmark = options[:bookmark]
        @icon = options[:icon]

        initialize_html_options(options)
      end

      # @return [Boolean] whether the ribbon has an icon
      def has_icon?
        @icon.present?
      end

      # @return [Boolean] whether the ribbon has visible text content
      def has_text?
        @text.present?
      end

      # @return [Hash] attributes for the root element (part :root), merged
      #   with whatever the caller supplied via html:.
      def root_attributes
        html_for(:root, class: ribbon_classes)
      end

      private

      # The base .ribbon CSS rule already positions near the top and on the
      # right, so :top/:end (both defaults) render no extra class. The CSS
      # only defines a "ribbon-start" class -- "ribbon-left" is the legacy
      # name and is never emitted here.
      def ribbon_classes
        classes = ["ribbon"]
        classes << "ribbon-bottom" if @position == :bottom
        classes << "ribbon-start" if @align == :start
        classes << "ribbon-bookmark" if @bookmark
        classes << "bg-#{@color}" if @color
        classes.join(" ")
      end
    end
  end
end
