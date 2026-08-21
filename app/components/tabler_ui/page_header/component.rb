# frozen_string_literal: true

module TablerUi
  module PageHeader
    # Page header component for Tabler UI. Renders the `.page-header` block
    # used atop a page: an optional `.page-pretitle`, the `h2.page-title`,
    # and a right-aligned `buttons` slot for page-level actions.
    #
    # @example Basic usage
    #   <%= tabler_ui.page_header title: "Dashboard" %>
    #
    # @example With a pretitle
    #   <%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview" %>
    #
    # @example No mandatory argument at all
    #   <%= tabler_ui.page_header %>
    #
    # @example With a buttons slot -- the block receives a single SlotContext
    #   <%= tabler_ui.page_header title: "Dashboard" do |slots| %>
    #     <% slots.buttons do %>
    #       <%= tabler_ui.button text: "New report", color: "primary" %>
    #     <% end %>
    #   <% end %>
    #
    # @example HTML attributes
    #   <%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview",
    #                             html: { class: "mb-4" },
    #                             title_html: { class: "text-uppercase" },
    #                             pretitle_html: { data: { testid: "pretitle" } },
    #                             buttons_html: { class: "gap-2" } %>
    #
    # @example Border, large title and a subtitle
    #   <%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview",
    #                             subtitle: "Last 30 days", border: true,
    #                             title_size: "lg" %>
    class Component
      include TablerUi::Base

      # Valid values for `title_size:`. A list rather than a boolean so it
      # can grow if Tabler adds more `.page-title-*` size variants.
      TITLE_SIZES = %w[lg].freeze

      attr_reader :title, :pretitle, :subtitle, :title_size

      # @param options [Hash]
      # @option options [String] :title    Page title, rendered in an
      #   `h2.page-title` (part :title)
      # @option options [String] :pretitle Small label above the title (part
      #   :pretitle), only when present. Distinct from :subtitle.
      # @option options [String] :subtitle Small label below the title (part
      #   :subtitle), only when present. Can be combined with :pretitle.
      # @option options [Boolean] :border  Appends `page-header-border` to
      #   the root element (part :root) when true.
      # @option options [String] :title_size "lg" adds `page-title-lg` (part
      #   :title). Any other value raises ArgumentError.
      # @option options [Hash] :html          HTML attributes for the
      #   outermost `.page-header` element (part :root)
      # @option options [Hash] :title_html    HTML attributes for the
      #   `h2.page-title` (part :title)
      # @option options [Hash] :pretitle_html HTML attributes for the
      #   `.page-pretitle` div (part :pretitle), only used when a pretitle
      #   renders
      # @option options [Hash] :subtitle_html HTML attributes for the
      #   `.page-subtitle` div (part :subtitle), only used when a subtitle
      #   renders
      # @option options [Hash] :buttons_html  HTML attributes for the
      #   right-aligned buttons column (part :buttons), only used when the
      #   `buttons` slot has content
      def initialize(options = {})
        @title = options[:title]
        @pretitle = options[:pretitle]
        @subtitle = options[:subtitle]
        @border = options[:border]
        @title_size = validate_title_size(options[:title_size])

        initialize_html_options(options)
      end

      # @return [Boolean] whether a pretitle should be rendered
      def pretitle?
        @pretitle.present?
      end

      # @return [Boolean] whether a subtitle should be rendered
      def subtitle?
        @subtitle.present?
      end

      # @return [Boolean] whether the root element carries the
      #   `page-header-border` class
      def border?
        @border.present?
      end

      # @return [Hash] attributes for the outermost element (part :root),
      #   merged with whatever the caller supplied via html:.
      def root_attributes
        html_for(:root, class: root_classes)
      end

      # @return [Hash] attributes for the `h2.page-title` (part :title),
      #   merged with whatever the caller supplied via title_html:.
      def title_attributes
        html_for(:title, class: title_classes)
      end

      # @return [Hash] attributes for the `.page-pretitle` div (part
      #   :pretitle), merged with whatever the caller supplied via
      #   pretitle_html:. Only used when pretitle? is true.
      def pretitle_attributes
        html_for(:pretitle, class: "page-pretitle")
      end

      # @return [Hash] attributes for the `.page-subtitle` div (part
      #   :subtitle), merged with whatever the caller supplied via
      #   subtitle_html:. Only used when subtitle? is true.
      def subtitle_attributes
        html_for(:subtitle, class: "page-subtitle")
      end

      # @return [Hash] attributes for the right-aligned buttons column (part
      #   :buttons), merged with whatever the caller supplied via
      #   buttons_html:. Only used when the buttons slot has content.
      def buttons_attributes
        html_for(:buttons, class: "col-auto ms-auto d-print-none")
      end

      private

      # @return [String] classes for the outermost element (part :root)
      def root_classes
        classes = ["page-header", "d-print-none", "mb-3"]
        classes << "page-header-border" if border?
        classes.join(" ")
      end

      # @return [String] classes for the `h2.page-title` (part :title)
      def title_classes
        classes = ["page-title"]
        classes << "page-title-#{@title_size}" if @title_size
        classes.join(" ")
      end

      # Validates `title_size:` against {TITLE_SIZES}, raising ArgumentError
      # naming the offender and the valid values. Passing nil returns nil
      # (title_size is optional).
      def validate_title_size(value)
        return nil if value.nil?

        value = value.to_s
        return value if TITLE_SIZES.include?(value)

        raise ArgumentError, "unknown title_size #{value.inspect} for page_header — valid: #{TITLE_SIZES.join(', ')}"
      end
    end
  end
end
