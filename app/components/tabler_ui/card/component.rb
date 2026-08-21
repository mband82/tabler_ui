# frozen_string_literal: true

module TablerUi
  module Card
    # Card component for Tabler UI. Renders a `.card` wrapper with optional
    # `.card-header`, `.card-body`, `.card-footer` parts, filled in via slots
    # (or a plain `title:` for a simple header).
    #
    # The block yields a single argument, the `SlotContext` -- `do |slots|`, not `do |card, slots|`.
    #
    # @example Basic usage -- title plus a body slot
    #   <%= tabler_ui.card title: "Card title" do |slots| %>
    #     <% slots.body do %>Card content<% end %>
    #   <% end %>
    #
    # @example Custom header content overrides title:
    #   <%= tabler_ui.card title: "Ignored" do |slots| %>
    #     <% slots.header do %><h3>Custom header</h3><% end %>
    #   <% end %>
    #
    # @example Footer slot
    #   <%= tabler_ui.card do |slots| %>
    #     <% slots.body do %>Content<% end %>
    #     <% slots.footer do %>Last updated 3 min ago<% end %>
    #   <% end %>
    #
    # @example Status strip, borderless, stacked, size
    #   <%= tabler_ui.card title: "x", status: "red", borderless: true,
    #                       stacked: true, size: "lg" %>
    #
    # @example Rule 5 hooks
    #   <%= tabler_ui.card title: "x", html: { class: "mb-4" },
    #                       header_html: { class: "bg-dark" },
    #                       body_html: { class: "p-0" },
    #                       footer_html: { class: "text-end" } do |slots| %>
    #     <% slots.body do %>Content<% end %>
    #   <% end %>
    class Component
      include TablerUi::Base

      # Valid values for `status_position:`. Each has a matching bare selector
      # in tabler.css (.card-status-top / -start / -bottom) that expects a
      # dedicated empty child div of `.card`, not classes on `.card` itself.
      STATUS_POSITIONS = %w[top start bottom].freeze

      attr_reader :title, :size, :status, :status_position, :borderless, :stacked

      # @param options [Hash]
      # @option options [String]  :title       Rendered as an `<h3 class="card-title">`
      #   inside the header when no `header` slot is given.
      # @option options [String, Symbol] :size Card size -- card-<size> (e.g. "sm", "lg")
      # @option options [String]  :status      Colour for a status strip child div --
      #   validated against TablerUi::Color. No strip is rendered without it.
      # @option options [String]  :status_position Where the strip sits -- "top" (default),
      #   "start" or "bottom". Has no effect without `status:`.
      # @option options [Boolean] :borderless  card-borderless (default: false)
      # @option options [Boolean] :stacked     card-stacked (default: false)
      # @option options [Hash]    :html        Rule 5 HTML hook for the outer `.card` (part :root)
      # @option options [Hash]    :header_html Rule 5 HTML hook for the `.card-header` (part :header)
      # @option options [Hash]    :body_html   Rule 5 HTML hook for the `.card-body` (part :body)
      # @option options [Hash]    :footer_html Rule 5 HTML hook for the `.card-footer` (part :footer)
      # @option options [Hash]    :status_html Rule 5 HTML hook for the status strip (part :status)
      def initialize(options = {})
        @title = options[:title]
        @size = options[:size]
        @status = TablerUi::Color.validate!(options[:status], context: "card")
        @status_position = validate_status_position(options[:status_position])
        @borderless = options[:borderless]
        @stacked = options[:stacked]

        initialize_html_options(options)
      end

      # @return [Boolean] whether a status strip is rendered
      def status?
        @status.present?
      end

      # @return [Hash] attributes for the outer element (part :root)
      def root_attributes
        html_for(:root, class: root_classes)
      end

      # @return [Hash] attributes for the `.card-header` (part :header)
      def header_attributes
        html_for(:header, class: "card-header")
      end

      # @return [Hash] attributes for the `.card-body` (part :body)
      def body_attributes
        html_for(:body, class: "card-body")
      end

      # @return [Hash] attributes for the `.card-footer` (part :footer)
      def footer_attributes
        html_for(:footer, class: "card-footer")
      end

      # @return [Hash] attributes for the status strip (part :status)
      def status_attributes
        html_for(:status, class: status_classes)
      end

      private

      def root_classes
        classes = ["card"]
        classes << "card-#{@size}" if @size.present?
        classes << "card-borderless" if @borderless
        classes << "card-stacked" if @stacked
        classes.join(" ")
      end

      def status_classes
        "card-status-#{@status_position} bg-#{@status}"
      end

      def validate_status_position(value)
        return "top" if value.nil?

        position = value.to_s
        return position if STATUS_POSITIONS.include?(position)

        raise ArgumentError,
              "unknown card status_position #{value.inspect} — valid: #{STATUS_POSITIONS.join(', ')}"
      end
    end
  end
end
