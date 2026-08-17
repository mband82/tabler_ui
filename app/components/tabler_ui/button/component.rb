# frozen_string_literal: true

module TablerUi
  module Button
    # Button component for Tabler UI. Renders a Bootstrap/Tabler styled
    # `<a>` (via `link_to`) when `method:` is the default `:get`, or a
    # `<form>`/`<button>` (via `button_to`) for any other HTTP method.
    #
    # @example Basic usage
    #   <%= tabler_ui.button text: "Save", color: "primary", url: "/save" %>
    #
    # @example Outline, sized, pill-shaped
    #   <%= tabler_ui.button text: "Cancel", color: "secondary", outline: true, size: :sm, shape: "pill" %>
    #
    # @example Destructive action
    #   <%= tabler_ui.button text: "Delete", color: "danger", url: "/widgets/1", method: :delete %>
    #
    # @example Icon-only action button
    #   <%= tabler_ui.button icon: "trash", icon_only: true, action: true, url: "/widgets/1", method: :delete %>
    #
    # @example Rule 5 hook on the root <a>/<button>
    #   <%= tabler_ui.button text: "Save", html: { class: "me-2", data: { testid: "save-button" } } %>
    class Component
      include TablerUi::Base

      attr_reader :text, :color, :outline, :size, :shape, :icon_only, :url,
                  :http_method, :target, :title, :disabled, :icon, :action

      # @param options [Hash]
      # @option options [String]  :text        Button label
      # @option options [String]  :color       Color variant -- validated against
      #   TablerUi::Color (Tabler palette + Bootstrap semantic names). Defaults to "primary".
      # @option options [Boolean] :outline     Outline variant, i.e. "btn-outline-<color>" (default: false)
      # @option options [String, Symbol] :size Button size, rendered as "btn-<size>"
      # @option options [String]  :shape       "pill" (rounded-pill) or "square" (btn-square)
      # @option options [Boolean] :icon_only   Icon-only style, i.e. "btn-icon" (default: false)
      # @option options [Boolean] :action      Action button style -- transparent/compact/hover-highlight
      #   ("btn-action"), replacing the color/outline/shape/icon_only classes (default: false)
      # @option options [String]  :url         URL for the button (default: "#")
      # @option options [Symbol, String] :method HTTP method. :get (default) renders `link_to`;
      #   any other value renders `button_to`.
      # @option options [String]  :target      Rendered as target="..."
      # @option options [String]  :title       Rendered as title="..."
      # @option options [Boolean] :disabled    Rendered as disabled="..."
      # @option options [Hash]    :data        Data attributes, merged with the html: hook's :data
      # @option options [String]  :icon        Tabler icon name, rendered before the text
      # @option options [Hash]    :html        Rule 5 HTML hook for the root <a>/<button> (part :root)
      def initialize(options = {})
        @action = options[:action]
        @text = options.key?(:text) ? options[:text] : default_text
        @color = TablerUi::Color.validate!(options[:color], context: "button") || "primary"
        @outline = options[:outline]
        @size = options[:size]
        @shape = options[:shape]
        @icon_only = options[:icon_only]
        @url = options[:url].presence || "#"
        @http_method = options[:method] || :get
        @target = options[:target]
        @title = options[:title]
        @disabled = options[:disabled]
        @data = options[:data]
        @icon = options[:icon]

        initialize_html_options(options)
      end

      # @return [Boolean] whether the button renders via `link_to` (true) or `button_to` (false)
      def get?
        @http_method.to_s == "get"
      end

      # @return [Boolean] whether the button has an icon to render before its text
      def has_icon?
        @icon.present?
      end

      # @return [Hash] attributes for the root <a>/<button> (part :root),
      #   merged with whatever the caller supplied via html:. Does not
      #   include :method -- callers rendering via `button_to` add that
      #   themselves, since it would otherwise leak onto `link_to` as a
      #   literal method="..." HTML attribute.
      def root_attributes
        defaults = {
          class: button_classes,
          target: @target,
          title: @title,
          disabled: @disabled
        }
        defaults[:data] = @data if @data.present?

        html_for(:root, defaults)
      end

      private

      def default_text
        @action ? nil : "Button"
      end

      def button_classes
        return action_classes if @action

        classes = [
          "btn",
          "btn-#{outline_prefix}#{@color}",
          size_class,
          shape_class,
          (@icon_only ? "btn-icon" : nil)
        ]

        classes.reject(&:blank?).join(" ")
      end

      def action_classes
        classes = ["btn", "btn-action", size_class]

        classes.reject(&:blank?).join(" ")
      end

      def outline_prefix
        @outline ? "outline-" : ""
      end

      def size_class
        @size.present? ? "btn-#{@size}" : nil
      end

      def shape_class
        case @shape.to_s
        when "pill" then "rounded-pill"
        when "square" then "btn-square"
        end
      end
    end
  end
end
