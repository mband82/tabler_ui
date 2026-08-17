# frozen_string_literal: true

module TablerUi
  module Rating
    # Star rating input for Tabler UI. Renders a single <select> wired up to
    # the `tabler-ui--rating` Stimulus controller
    # (app/javascript/controllers/tabler_ui/rating_controller.js), which
    # replaces it with a star-rating.js widget.
    #
    # @example Basic usage
    #   <%= tabler_ui.rating %>
    #
    # @example Custom choices, 3-star scale, colored
    #   <%= tabler_ui.rating choices: [{ value: 1, label: "Bad" }, { value: 2, label: "Ok" }, { value: 3, label: "Great" }],
    #                        max_stars: 3, color: "yellow" %>
    #
    # @example Rule 5 hook on the <select>
    #   <%= tabler_ui.rating html: { class: "me-2", data: { testid: "rating" } } %>
    class Component
      include TablerUi::Base

      attr_reader :id, :name, :value, :required, :disabled, :size, :color, :tooltip, :clearable, :max_stars

      # @param options [Hash]
      # @option options [String]  :id        HTML id (default: generated "rating-<hex>")
      # @option options [String]  :name      <select> name (default: "rating")
      # @option options [Object]  :value     Currently selected value
      # @option options [Array<Hash>] :choices List of { value:, label: } choices. Defaults to
      #   #default_choices, a scale from "Excellent" down to "Terrible" sized to max_stars.
      # @option options [Boolean] :required  (default: false)
      # @option options [Boolean] :disabled  (default: false)
      # @option options [String]  :size      Forwarded to the Stimulus controller / star-rating.js
      # @option options [String]  :color     Validated with TablerUi::Color.validate! (nil is valid)
      # @option options [Boolean] :tooltip   (default: true)
      # @option options [Boolean] :clearable (default: true)
      # @option options [Integer] :max_stars (default: 5)
      # @option options [Hash]    :html      Rule 5 HTML hook for the <select> (part :root)
      def initialize(options = {})
        @id = options[:id] || "rating-#{SecureRandom.hex(4)}"
        @name = options.fetch(:name, "rating")
        @value = options[:value]
        @choices = options[:choices]
        @required = options.fetch(:required, false)
        @disabled = options.fetch(:disabled, false)
        @size = options[:size]
        @color = TablerUi::Color.validate!(options[:color], context: "rating")
        @tooltip = options.fetch(:tooltip, true)
        @clearable = options.fetch(:clearable, true)
        @max_stars = options.fetch(:max_stars, 5)

        initialize_html_options(options)
      end

      # @return [Array<Hash>] the choices to render as <option>s -- whatever
      #   the caller passed via choices:, or #default_choices computed lazily
      #   (so it always sees the final @max_stars, however initialize ordered
      #   its assignments).
      def choices
        @choices || default_choices
      end

      # @return [Array<Hash>] a default rating scale from "Excellent" down to
      #   "Terrible", sized to max_stars (plus the blank "Select a rating"
      #   placeholder).
      def default_choices
        [
          { value: "", label: "Select a rating" },
          { value: max_stars, label: "Excellent" },
          { value: max_stars - 1, label: "Very Good" },
          { value: max_stars - 2, label: "Average" },
          { value: max_stars - 3, label: "Poor" },
          { value: max_stars - 4, label: "Terrible" }
        ].slice(0, max_stars + 1)
      end

      # @return [Hash] the data-* attributes the tabler-ui--rating Stimulus
      #   controller (see rating_controller.js `static values`) expects.
      def controller_attributes
        {
          controller: "tabler-ui--rating",
          "tabler-ui--rating-id-value" => id,
          "tabler-ui--rating-tooltip-value" => tooltip,
          "tabler-ui--rating-clearable-value" => clearable,
          "tabler-ui--rating-color-value" => color,
          "tabler-ui--rating-size-value" => size
        }
      end

      # @return [Hash] attributes for the <select> (part :root), merged with
      #   whatever the caller supplied via html:.
      def root_attributes
        html_for(:root,
                 id: id,
                 class: "form-select",
                 required: required,
                 disabled: disabled,
                 data: controller_attributes)
      end
    end
  end
end
