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
    # @example HTML attributes on the <select>
    #   <%= tabler_ui.rating html: { class: "me-2", data: { testid: "rating" } } %>
    class Component
      include TablerUi::Base

      attr_reader :id, :name, :value, :required, :disabled, :size, :color, :tooltip, :clearable, :max_stars

      # @param options [Hash]
      # @option options [String]  :id        HTML id (default: deterministic, derived from :name)
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
      # @option options [Hash]    :html      HTML attributes for the <select> (part :root)
      # @option options [Hash]    :wrapper_html HTML attributes for the wrapping
      #   <span> (part :wrapper) that carries the Stimulus controller. The
      #   controller lives here, not on the <select>.
      #
      # `:id` defaults to a value derived from `:name`. If two ratings share
      # the same `:name` on one page, pass `:id` explicitly to avoid duplicate
      # DOM ids.
      def initialize(options = {})
        @name = options.fetch(:name, "rating")
        @id = options[:id] || default_id(@name)
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
          "tabler-ui--rating-tooltip-value" => tooltip,
          "tabler-ui--rating-clearable-value" => clearable,
          "tabler-ui--rating-color-value" => color,
          "tabler-ui--rating-size-value" => size
        }
      end

      # @return [Hash] attributes for the wrapping <span> (part :wrapper) that
      #   carries the tabler-ui--rating Stimulus controller, merged with
      #   whatever the caller supplied via wrapper_html:.
      #
      #   The controller must NOT live on the <select> itself. star-rating.js
      #   (app/assets/javascripts/star-rating.js#buildWidget) replaces the
      #   <select> in place: it inserts a wrapper span next to it, then
      #   reparents the <select> inside that new span. If the Stimulus
      #   controller is attached to the <select>, Stimulus's own DOM observer
      #   sees that reparenting as "the controller's element was removed, then
      #   a new one was added" and fires disconnect() then connect() --
      #   disconnect() tears the widget down (moving the <select> right back
      #   out again, per Widget#destroy's `replaceChild`), which is itself
      #   another reparenting Stimulus reacts to, triggering another
      #   connect() that rebuilds the widget and reparents again. That is an
      #   unbounded connect -> mutate DOM -> disconnect -> mutate DOM ->
      #   connect loop with no thrown error, which pegs the main thread and
      #   crashes/hangs the tab.
      #
      #   Putting the controller on a stable outer <span> instead fixes this:
      #   star-rating.js only ever moves the <select> *within* that span's
      #   subtree (first as a direct child, later one level deeper inside its
      #   own `.gl-star-rating` wrapper), so the controller's own root element
      #   is never removed or reparented, and Stimulus never disconnects it.
      #   rating_controller.js points the library at the <select> via a
      #   `select` target rather than an id selector, for the same reason.
      def wrapper_attributes
        html_for(:wrapper, class: "tabler-ui-rating", data: controller_attributes)
      end

      # @return [Hash] attributes for the <select> (part :root), merged with
      #   whatever the caller supplied via html:.
      def root_attributes
        html_for(:root,
                 id: id,
                 class: "form-select",
                 required: required,
                 disabled: disabled,
                 data: { "tabler-ui--rating-target" => "select" })
      end

      private

      # @param name [String, Symbol] the rating's :name
      # @return [String] a deterministic id derived from name -- keeps
      #   rendered output cache-stable across identical requests (see the
      #   :id option docs above). Falls back to "rating" when name
      #   parameterizes to blank (e.g. a name: made entirely of
      #   non-alphanumeric characters).
      def default_id(name)
        "rating-#{name.to_s.parameterize.presence || 'rating'}"
      end
    end
  end
end
