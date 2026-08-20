# frozen_string_literal: true

module TablerUi
  module Toast
    # Toast component for Tabler UI. Renders a single Bootstrap-driven
    # `.toast` (optionally wrapped in a positioned `.toast-container`), with
    # `.toast-header` / `.toast-body` parts filled in via slots (or a plain
    # `title:` for a simple header).
    #
    # The component renders no trigger -- if you want click-to-show behaviour
    # put `data-bs-toggle="toast" data-bs-target="#<id>"` on your own
    # button/link, exactly like Bootstrap's own docs (give the toast an `id:`
    # via `html: { id: ... }` to target). `tabler.js` scans the DOM for such
    # triggers *once*, at script-load time (see
    # `app/assets/javascripts/tabler_ui/tabler.js`, the "Toasts" block), so
    # that wiring only reaches triggers present in the initial page load --
    # a toast/trigger pair inserted later via Turbo needs to be shown some
    # other way (e.g. calling `.show()` on the adopted instance yourself).
    # That is an existing `tabler.js` limitation, not something this
    # component's controller works around -- see
    # `app/javascript/controllers/tabler_ui/toast_controller.js` for why the
    # controller deliberately does *not* bind its own trigger click handler.
    #
    # @example Basic usage -- title plus body slot
    #   <%= tabler_ui.toast title: "Success", color: "success" do |slots| %>
    #     <% slots.body { "Changes saved." } %>
    #   <% end %>
    #
    # @example Custom header content overrides title:
    #   <%= tabler_ui.toast do |slots| %>
    #     <% slots.header { "Custom header".html_safe } %>
    #     <% slots.body { "Body text" } %>
    #   <% end %>
    #
    # @example Autohide tuning
    #   <%= tabler_ui.toast title: "Heads up", autohide: false %>
    #   <%= tabler_ui.toast title: "Heads up", delay: 8000 %>
    #
    # @example Fixed placement (see #position for the full vocabulary)
    #   <%= tabler_ui.toast title: "Saved", position: "top-right" %>
    #
    # @example Suppress the close button
    #   <%= tabler_ui.toast title: "Saved", close_button: false %>
    #
    # @example Rule 5 hooks
    #   <%= tabler_ui.toast title: "Saved", position: "top-right",
    #                       html:           { class: "mb-2" },
    #                       header_html:    { class: "bg-dark" },
    #                       body_html:      { data: { controller: "foo" } },
    #                       container_html: { class: "p-4" } %>
    #
    # ## Accessibility
    #
    # The root `.toast` carries `role="alert"`, `aria-live="assertive"` and
    # `aria-atomic="true"` -- Bootstrap's own default recommendation for
    # toasts, since they are meant to interrupt. A caller that wants the
    # gentler `role="status" aria-live="polite"` pairing (e.g. a low-priority
    # background notification) can override both via the `html:` hook, since
    # rule 5 hooks overwrite non-class attributes rather than only appending.
    # The close button carries its own translated aria-label
    # (tabler_ui.toast.close), matching modal's approach.
    class Component
      include TablerUi::Base

      POSITIONS = %w[
        top-left top-center top-right
        middle-left middle-center middle-right
        bottom-left bottom-center bottom-right
      ].freeze

      POSITION_CLASSES = {
        "top-left" => %w[top-0 start-0],
        "top-center" => %w[top-0 start-50 translate-middle-x],
        "top-right" => %w[top-0 end-0],
        "middle-left" => %w[top-50 start-0 translate-middle-y],
        "middle-center" => %w[top-50 start-50 translate-middle],
        "middle-right" => %w[top-50 end-0 translate-middle-y],
        "bottom-left" => %w[bottom-0 start-0],
        "bottom-center" => %w[bottom-0 start-50 translate-middle-x],
        "bottom-right" => %w[bottom-0 end-0]
      }.freeze

      attr_reader :title, :color, :autohide, :delay, :close_button, :position

      # @param options [Hash]
      # @option options [String]  :title        Rendered as a `<strong class="me-auto">`
      #   inside the header when no `header` slot is given.
      # @option options [String]  :color        Colour for the toast -- validated against
      #   TablerUi::Color (both the Tabler palette and the semantic names are
      #   supported for toast, unlike `steps`), rendered as `toast-<color>`.
      # @option options [Boolean] :autohide     Maps to `data-bs-autohide` -- Bootstrap
      #   defaults this to true itself, so it's only rendered when given explicitly.
      # @option options [Integer] :delay        Milliseconds before autohide fires --
      #   maps to `data-bs-delay`. Bootstrap defaults this to 5000 itself, so it's only
      #   rendered when given explicitly.
      # @option options [Boolean] :close_button Whether to render the `.btn-close` (default: true)
      # @option options [String]  :position     Fixed placement -- wraps the toast in a
      #   `.toast-container.position-fixed` (see #position for the full vocabulary and
      #   why a container is opt-in). Stacking several toasts in one container is left to
      #   the caller (render one `tabler_ui.toast` per notification, no `position:`, inside
      #   your own `.toast-container`).
      # @option options [Hash]    :html           Rule 5 HTML hook for the root `.toast` (part :root)
      # @option options [Hash]    :header_html    Rule 5 HTML hook for the `.toast-header` (part :header)
      # @option options [Hash]    :body_html      Rule 5 HTML hook for the `.toast-body` (part :body)
      # @option options [Hash]    :container_html Rule 5 HTML hook for the `.toast-container`,
      #   when `position:` is given (part :container)
      # @option options [Hash]    :close_html     Rule 5 HTML hook for the `.btn-close`
      #   button, when `close_button:` is true (part :close)
      #
      # @example close_html: -- Rule 5 hook on the close button
      #   <%= tabler_ui.toast title: "Saved", close_html: { class: "me-1", data: { testid: "dismiss" } } %>
      def initialize(options = {})
        @title = options[:title]
        @color = TablerUi::Color.validate!(options[:color], context: "toast")
        @autohide = options[:autohide]
        @autohide_given = options.key?(:autohide)
        @delay = options[:delay]
        @close_button = options.key?(:close_button) ? options[:close_button] : true
        @position = validate_position(options[:position])

        initialize_html_options(options)
      end

      # @return [Boolean] whether `position:` was given, i.e. whether a
      #   `.toast-container` is rendered around the toast
      def positioned?
        position.present?
      end

      # @return [String] translated aria-label for the `.btn-close`
      def close_label
        I18n.t("tabler_ui.toast.close")
      end

      # @return [Hash] attributes for the `.toast-container`, when rendered (part :container)
      def container_attributes
        html_for(:container, class: container_classes)
      end

      # @return [Hash] attributes for the root `.toast` element (part :root)
      def root_attributes
        defaults = {
          class: root_classes,
          role: "alert",
          "aria-live": "assertive",
          "aria-atomic": "true",
          data: root_data_attributes
        }

        html_for(:root, defaults)
      end

      # @return [Hash] attributes for the `.toast-header` (part :header)
      def header_attributes
        html_for(:header, class: "toast-header")
      end

      # @return [Hash] attributes for the `.toast-body` (part :body)
      def body_attributes
        html_for(:body, class: "toast-body")
      end

      # @return [Hash] attributes for the `.btn-close` button (part :close),
      #   rendered when `close_button:` is true
      def close_attributes
        html_for(:close,
                 type: "button",
                 class: "btn-close",
                 "data-bs-dismiss": "toast",
                 "aria-label": close_label)
      end

      private

      # A `.toast-container` is only rendered when `position:` is given.
      # Every toast getting its own container-per-instance by default would
      # make stacking (several toasts occupying the same corner) impossible
      # without the caller fighting the component's own wrapper, so a bare
      # `tabler_ui.toast` renders just the `.toast` element -- callers who
      # want several toasts sharing one fixed corner wrap them together in
      # their own `.toast-container` and skip `position:` on each.
      def container_classes
        (["toast-container", "position-fixed", "p-3"] + POSITION_CLASSES.fetch(position)).join(" ")
      end

      def root_classes
        classes = ["toast"]
        classes << "toast-#{color}" if color.present?
        classes.join(" ")
      end

      def root_data_attributes
        data = { controller: "tabler-ui--toast" }
        data[:bs_autohide] = autohide if @autohide_given
        data[:bs_delay] = delay if delay.present?
        data
      end

      def validate_position(value)
        return nil if value.nil?

        position = value.to_s
        return position if POSITIONS.include?(position)

        raise ArgumentError,
              "unknown toast position #{value.inspect} — valid: #{POSITIONS.join(', ')}"
      end
    end
  end
end
