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
    # @example Rule 5 hooks
    #   <%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview",
    #                             html: { class: "mb-4" },
    #                             title_html: { class: "text-uppercase" },
    #                             pretitle_html: { data: { testid: "pretitle" } },
    #                             buttons_html: { class: "gap-2" } %>
    class Component
      include TablerUi::Base

      attr_reader :title, :pretitle

      # @param options [Hash]
      # @option options [String] :title    Page title, rendered in an
      #   `h2.page-title` (part :title)
      # @option options [String] :pretitle Small label rendered above the
      #   title in `.page-pretitle` (part :pretitle), only when present.
      #   Matches Tabler's own `page-pretitle` CSS class and the element's
      #   position above the title -- not a subtitle.
      # @option options [Hash] :html          Rule 5 HTML hook for the
      #   outermost `.page-header` element (part :root)
      # @option options [Hash] :title_html    Rule 5 HTML hook for the
      #   `h2.page-title` (part :title)
      # @option options [Hash] :pretitle_html Rule 5 HTML hook for the
      #   `.page-pretitle` div (part :pretitle), only used when a pretitle
      #   renders
      # @option options [Hash] :buttons_html  Rule 5 HTML hook for the
      #   right-aligned buttons column (part :buttons), only used when the
      #   `buttons` slot has content
      def initialize(options = {})
        @title = options[:title]
        @pretitle = options[:pretitle]

        initialize_html_options(options)
      end

      # @return [Boolean] whether a pretitle should be rendered
      def pretitle?
        @pretitle.present?
      end

      # @return [Hash] attributes for the outermost element (part :root),
      #   merged with whatever the caller supplied via html:.
      def root_attributes
        html_for(:root, class: "page-header d-print-none mb-3")
      end

      # @return [Hash] attributes for the `h2.page-title` (part :title),
      #   merged with whatever the caller supplied via title_html:.
      def title_attributes
        html_for(:title, class: "page-title")
      end

      # @return [Hash] attributes for the `.page-pretitle` div (part
      #   :pretitle), merged with whatever the caller supplied via
      #   pretitle_html:. Only used when pretitle? is true.
      def pretitle_attributes
        html_for(:pretitle, class: "page-pretitle")
      end

      # @return [Hash] attributes for the right-aligned buttons column (part
      #   :buttons), merged with whatever the caller supplied via
      #   buttons_html:. Only used when the buttons slot has content.
      def buttons_attributes
        html_for(:buttons, class: "col-auto ms-auto d-print-none")
      end
    end
  end
end
