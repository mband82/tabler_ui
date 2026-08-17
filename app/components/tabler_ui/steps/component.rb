# frozen_string_literal: true

module TablerUi
  module Steps
    # Steps component for Tabler UI. Renders a wizard/progress step
    # indicator. Builder-style: the block yields the component itself, and
    # steps are added via #item.
    #
    # @example Basic usage
    #   <%= tabler_ui.steps do |steps| %>
    #     <% steps.item("Account") %>
    #     <% steps.item("Profile") %>
    #     <% steps.item("Confirm") %>
    #   <% end %>
    #
    # @example Marking progress, vertical layout, numbered dots
    #   <%= tabler_ui.steps(current: 2, vertical: true, counter: true) do |steps| %>
    #     <% steps.item("Account") %>
    #     <% steps.item("Profile") %>
    #     <% steps.item("Confirm") %>
    #   <% end %>
    #
    # @example Linking earlier steps back
    #   <%= tabler_ui.steps(current: 3) do |steps| %>
    #     <% steps.item("Account", url: account_path) %>
    #     <% steps.item("Profile", url: profile_path) %>
    #     <% steps.item("Confirm") %>
    #   <% end %>
    #
    # @example Colour, light variant, and rule 5 hooks
    #   <%= tabler_ui.steps(color: "azure", light: true, html: { class: "mb-3" }) do |steps| %>
    #     <% steps.item("Account", html: { class: "fw-bold" }) %>
    #     <% steps.item("Profile", html: ->(item) { { class: "text-muted" } if item.title == "Profile" }) %>
    #   <% end %>
    #
    # The CSS (.step-item.active ~ .step-item dims everything after the
    # active step) only makes sense with exactly one active step, so there is
    # no per-item `active:` flag -- the single `current:` index on the
    # component is the only source of truth for which step is active.
    class Component
      include TablerUi::Base
      builder_style!

      # :html holds the caller's *raw* per-item hook (Hash or Proc taking the
      # item), not resolved attributes -- see #item_attributes. :index is
      # 0-based and set by #item in call order, so #active? can compare it
      # against `current:` without relying on Struct value-equality (two
      # items with the same title/url/html would otherwise look identical to
      # Array#index).
      Item = Struct.new(:title, :url, :html, :index, keyword_init: true)

      attr_reader :items, :current

      # @param options [Hash]
      # @option options [Integer] :current  1-based index of the active step
      #   (default: 1). Items are added after the component is constructed,
      #   so this can only be checked against the final item count once
      #   rendering starts -- see #root_attributes. Out of range (< 1 or
      #   > number of items) raises ArgumentError naming the component.
      # @option options [Boolean] :vertical Render as a vertical list (steps-vertical)
      # @option options [Boolean] :counter  Number the dots instead of plain dots (steps-counter)
      # @option options [String]  :color    Tabler palette colour name --
      #   TablerUi::Color::TABLER (blue, azure, indigo, ...). The stylesheet
      #   only defines steps-<color>[-lt] for that raw palette, not the
      #   Bootstrap semantic names (primary, success, ...) that
      #   TablerUi::Color::ALL also accepts on other components, so an
      #   unknown or semantic name raises ArgumentError rather than emitting
      #   a class the stylesheet does not define.
      # @option options [Boolean] :light    Use the light/subtle variant
      #   (steps-<color>-lt). Only has an effect when :color is also given --
      #   there is no colourless steps-lt class in the stylesheet.
      # @option options [Hash]    :html     Rule 5 HTML hook for the outer list (part :root)
      def initialize(options = {})
        @current = options.fetch(:current, 1)
        @vertical = options[:vertical]
        @counter = options[:counter]
        @color = validate_color!(options[:color])
        @light = options[:light]
        @items = []

        initialize_html_options(options)
      end

      # Adds a step.
      #
      # @param title [String] Step text
      # @param options [Hash]
      # @option options [String] :url Step URL -- renders an <a> when given;
      #   a plain <li> (no link) otherwise
      # @option options [Hash, #call] :html Rule 5 HTML hook for this step's
      #   element (part :item) -- a plain Hash, or a callable taking the item
      # @return [String] empty string, to avoid stray output in a capture context
      def item(title, options = {})
        builder_argument!(title, :title, builder: :item)

        @items << Item.new(title: title, url: options[:url], html: options[:html], index: @items.length)

        ""
      end

      # @return [Hash] attributes for the outer list (part :root).
      def root_attributes
        html_for(:root, class: root_classes,
                         aria: { label: I18n.t("tabler_ui.steps.label") })
      end

      # @param item [Item] the item being rendered
      # @return [Boolean] whether this is the current/active step
      def active?(item)
        item.index == current_index
      end

      # @param item [Item] the item being rendered
      # @return [Hash] attributes for this item's element (part :item)
      def item_attributes(item)
        @tabler_ui_html_options[:item] = item.html
        html_for(:item, item_html_defaults(item), item)
      end

      # Called by TablerUi::Ui once the builder block has run and every item is
      # known -- :current can only be range-checked against a complete list.
      # Validating here rather than in the template keeps the error an
      # ArgumentError instead of an ActionView::Template::Error wrapping one.
      def validate!
        return if @items.empty?
        return if (1..@items.length).cover?(@current)

        raise ArgumentError,
              "steps current: #{@current.inspect} is out of range -- valid: 1..#{@items.length}"
      end

      private

      def item_html_defaults(item)
        defaults = { class: item_classes(item) }
        defaults[:aria] = { current: "step" } if active?(item)
        defaults
      end

      def current_index
        @current - 1
      end

      def validate_color!(color)
        return nil if color.nil?

        color = color.to_s
        return color if TablerUi::Color::TABLER.include?(color)

        raise ArgumentError,
              "unknown color #{color.inspect} for steps — valid: #{TablerUi::Color::TABLER.join(', ')}"
      end

      def root_classes
        classes = ["steps"]
        classes << "steps-vertical" if @vertical
        classes << "steps-counter" if @counter
        classes << "steps-#{@color}#{'-lt' if @light}" if @color
        classes.join(" ")
      end

      def item_classes(item)
        classes = ["step-item"]
        classes << "active" if active?(item)
        classes.join(" ")
      end
    end
  end
end
