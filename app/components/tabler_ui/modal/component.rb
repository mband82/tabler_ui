# frozen_string_literal: true

module TablerUi
  module Modal
    # Modal component for Tabler UI. Renders the three-level
    # `.modal > .modal-dialog > .modal-content` structure Bootstrap's Modal
    # JS requires (it does `SelectorEngine.findOne('.modal-dialog', el)`),
    # with optional `.modal-header` / `.modal-body` / `.modal-footer` parts
    # filled in via slots (or a plain `title:` for a simple header).
    #
    # The component renders no trigger -- put `data-bs-toggle="modal"
    # data-bs-target="#<id>"` on your own button/link, exactly like
    # Bootstrap's own docs, and consistent with how `collapse_controller`
    # attaches to the collapsible element rather than the toggler.
    #
    # @example Basic usage -- title plus body/footer slots
    #   <button data-bs-toggle="modal" data-bs-target="#my-modal">Open</button>
    #   <%= tabler_ui.modal "my-modal", title: "Confirm" do |slots| %>
    #     <% slots.body do %>Are you sure?<% end %>
    #     <% slots.footer do %>
    #       <button class="btn btn-primary">Yes</button>
    #     <% end %>
    #   <% end %>
    #
    # @example Custom header content overrides title:
    #   <%= tabler_ui.modal "my-modal" do |slots| %>
    #     <% slots.header do %><h3>Custom header</h3><% end %>
    #   <% end %>
    #
    # @example Size, centered, scrollable, blur, status strip
    #   <%= tabler_ui.modal "my-modal", size: "lg", centered: true,
    #                       scrollable: true, blur: true, status: "red" %>
    #
    # @example Suppress the close button
    #   <%= tabler_ui.modal "my-modal", close_button: false %>
    #
    # @example Rule 5 hooks
    #   <%= tabler_ui.modal "my-modal", title: "Confirm",
    #                       html: { class: "mb-4" },
    #                       dialog_html: { class: "modal-lg" },
    #                       content_html: { class: "border-0" },
    #                       header_html: { class: "bg-dark" },
    #                       body_html:   { data: { controller: "foo" } },
    #                       footer_html: { class: "text-end" } %>
    #
    # ## Accessibility
    #
    # The root `.modal` carries `tabindex="-1"`, `role="dialog"`, and either
    # `aria-labelledby` (pointing at the id of the rendered `.modal-title`)
    # when a title is actually showing, or a translated `aria-label` when it
    # isn't -- no title: given, or a header slot that overrides it (see
    # config/locales/en.yml, tabler_ui.modal.dialog_label). The close button
    # carries its own translated aria-label (tabler_ui.modal.close).
    #
    # Note: the block yields exactly one argument, the SlotContext --
    # `do |slots|`, not `do |modal, slots|`.
    class Component
      include TablerUi::Base

      SIZES = %w[sm lg xl fullscreen].freeze

      attr_reader :id, :title, :size, :centered, :scrollable, :blur, :status, :close_button

      # @param id [String] Mandatory DOM id for the `.modal` root -- the
      #   anchor a caller's own toggler points at via
      #   `data-bs-toggle="modal" data-bs-target="##{id}"`.
      # @param options [Hash]
      # @option options [String]  :title        Rendered as an `<h5 class="modal-title">`
      #   inside the header when no `header` slot is given.
      # @option options [String, Symbol] :size  Dialog size -- "sm", "lg", "xl", or
      #   "fullscreen" (renders `modal-fullscreen`, not `modal-modal-fullscreen`)
      # @option options [Boolean] :centered     modal-dialog-centered (default: false)
      # @option options [Boolean] :scrollable   modal-dialog-scrollable (default: false)
      # @option options [Boolean] :blur         modal-blur (backdrop blur) on the root (default: false)
      # @option options [String]  :status       Colour for a `.modal-status` strip --
      #   validated against TablerUi::Color
      # @option options [Boolean] :close_button Whether to render the `.btn-close` (default: true)
      # @option options [Hash]    :html         Rule 5 HTML hook for the root `.modal` (part :root)
      # @option options [Hash]    :dialog_html  Rule 5 HTML hook for the `.modal-dialog` (part :dialog)
      # @option options [Hash]    :content_html Rule 5 HTML hook for the `.modal-content` (part :content)
      # @option options [Hash]    :header_html  Rule 5 HTML hook for the `.modal-header` (part :header)
      # @option options [Hash]    :body_html    Rule 5 HTML hook for the `.modal-body` (part :body)
      # @option options [Hash]    :footer_html  Rule 5 HTML hook for the `.modal-footer` (part :footer)
      def initialize(id, options = {})
        @id = id
        @title = options[:title]
        @size = validate_size(options[:size])
        @centered = options[:centered]
        @scrollable = options[:scrollable]
        @blur = options[:blur]
        @status = TablerUi::Color.validate!(options[:status], context: "modal")
        @close_button = options.key?(:close_button) ? options[:close_button] : true

        initialize_html_options(options)
      end

      # @return [Boolean] whether a status strip is rendered
      def status?
        status.present?
      end

      # @return [String] id of the rendered `.modal-title`, used as the
      #   `aria-labelledby` target
      def title_id
        "#{id}-title"
      end

      # @return [String] translated aria-label for the root when no title is showing
      def dialog_label
        I18n.t("tabler_ui.modal.dialog_label")
      end

      # @return [String] translated aria-label for the `.btn-close`
      def close_label
        I18n.t("tabler_ui.modal.close")
      end

      # @param title_visible [Boolean] whether an `<h5 class="modal-title">`
      #   with id #title_id is actually rendered this pass -- depends on
      #   whether a header slot was given, which only the template knows, so
      #   it's handed in rather than guessed here. See the class docs'
      #   Accessibility section.
      # @return [Hash] attributes for the root `.modal` element (part :root)
      def root_attributes(title_visible: false)
        defaults = {
          id: id,
          class: root_classes,
          tabindex: "-1",
          role: "dialog",
          data: { controller: "tabler-ui--modal" }
        }
        defaults[title_visible ? :"aria-labelledby" : :"aria-label"] =
          title_visible ? title_id : dialog_label

        html_for(:root, defaults)
      end

      # @return [Hash] attributes for the `.modal-dialog` (part :dialog)
      def dialog_attributes
        html_for(:dialog, class: dialog_classes)
      end

      # @return [Hash] attributes for the `.modal-content` (part :content)
      def content_attributes
        html_for(:content, class: "modal-content")
      end

      # @return [Hash] attributes for the `.modal-header` (part :header)
      def header_attributes
        html_for(:header, class: "modal-header")
      end

      # @return [Hash] attributes for the `.modal-body` (part :body)
      def body_attributes
        html_for(:body, class: "modal-body")
      end

      # @return [Hash] attributes for the `.modal-footer` (part :footer)
      def footer_attributes
        html_for(:footer, class: "modal-footer")
      end

      private

      def root_classes
        classes = ["modal"]
        classes << "modal-blur" if blur
        classes.join(" ")
      end

      def dialog_classes
        classes = ["modal-dialog"]
        if size == "fullscreen"
          classes << "modal-fullscreen"
        elsif size.present?
          classes << "modal-#{size}"
        end
        classes << "modal-dialog-centered" if centered
        classes << "modal-dialog-scrollable" if scrollable
        classes.join(" ")
      end

      def validate_size(value)
        return nil if value.nil?

        size = value.to_s
        return size if SIZES.include?(size)

        raise ArgumentError,
              "unknown modal size #{value.inspect} — valid: #{SIZES.join(', ')}"
      end
    end
  end
end
