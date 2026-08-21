# frozen_string_literal: true

module TablerUi
  module Toast
    # Toast component for Tabler UI. Renders a single Bootstrap-driven
    # `.toast` (optionally wrapped in a positioned `.toast-container`), with
    # `.toast-header` / `.toast-body` parts filled in via slots (or a plain
    # `title:` for a simple header).
    #
    # The component renders no trigger -- put `data-bs-toggle="toast"
    # data-bs-target="#<id>"` on your own button/link (give the toast an
    # `id:` via `html: { id: ... }` to target). Trigger wiring is scanned
    # once at script-load time, so a toast/trigger pair inserted later via
    # Turbo needs to be shown some other way (e.g. calling `.show()` on the
    # adopted instance yourself).
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
    # @example HTML attributes
    #   <%= tabler_ui.toast title: "Saved", position: "top-right",
    #                       html:           { class: "mb-2" },
    #                       header_html:    { class: "bg-dark" },
    #                       body_html:      { data: { controller: "foo" } },
    #                       container_html: { class: "p-4" } %>
    #
    # ## Accessibility
    #
    # The root `.toast` carries `role="alert"`, `aria-live="assertive"` and
    # `aria-atomic="true"` by default. For a lower-priority notification,
    # override with `role="status" aria-live="polite"` via the `html:` hook.
    # The close button carries its own translated aria-label.
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
      # @option options [String]  :color        Colour for the toast, validated against
      #   TablerUi::Color, rendered as `toast-<color>`.
      # @option options [Boolean] :autohide     Maps to `data-bs-autohide`. Only rendered
      #   when given explicitly (Bootstrap defaults it to true itself).
      # @option options [Integer] :delay        Milliseconds before autohide fires, maps to
      #   `data-bs-delay`. Only rendered when given explicitly (Bootstrap defaults it to 5000).
      # @option options [Boolean] :close_button Whether to render the `.btn-close` (default: true)
      # @option options [String]  :position     Fixed placement -- wraps the toast in a
      #   `.toast-container.position-fixed`. One of `top-left`, `top-center`, `top-right`,
      #   `middle-left`, `middle-center`, `middle-right`, `bottom-left`, `bottom-center`,
      #   `bottom-right`. To stack several toasts in one corner, render each with no
      #   `position:` inside your own `.toast-container`.
      # @option options [Hash]    :html           HTML attributes for the root `.toast` (part :root)
      # @option options [Hash]    :header_html    HTML attributes for the `.toast-header` (part :header)
      # @option options [Hash]    :body_html      HTML attributes for the `.toast-body` (part :body)
      # @option options [Hash]    :container_html HTML attributes for the `.toast-container`,
      #   when `position:` is given (part :container)
      # @option options [Hash]    :close_html     HTML attributes for the `.btn-close`
      #   button, when `close_button:` is true (part :close)
      #
      # @example close_html: -- HTML attributes on the close button
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
