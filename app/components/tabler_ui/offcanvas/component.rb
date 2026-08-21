# frozen_string_literal: true

module TablerUi
  module Offcanvas
    # A single `.offcanvas.offcanvas-<edge>` panel, sliding in from one of
    # the four screen edges, with optional `.offcanvas-header` /
    # `.offcanvas-body` / `.offcanvas-footer` parts filled in via slots (or
    # a plain `title:` for a simple header).
    #
    # Renders no trigger -- add `data-bs-toggle="offcanvas"
    # data-bs-target="#<id>"` to your own button/link.
    #
    # @example Basic usage -- title plus body/footer slots
    #   <button data-bs-toggle="offcanvas" data-bs-target="#my-offcanvas">Open</button>
    #   <%= tabler_ui.offcanvas "my-offcanvas", title: "Filters" do |slots| %>
    #     <% slots.body do %>Filter form here<% end %>
    #     <% slots.footer do %>
    #       <button class="btn btn-primary">Apply</button>
    #     <% end %>
    #   <% end %>
    #
    # @example Custom header content overrides title: (and the built-in close button)
    #   <%= tabler_ui.offcanvas "my-offcanvas" do |slots| %>
    #     <% slots.header do %><h3>Custom header</h3><% end %>
    #   <% end %>
    #
    # @example Edge, narrow width, backdrop and scroll behaviour
    #   <%= tabler_ui.offcanvas "my-offcanvas", position: :end, narrow: true,
    #                           backdrop: :static, scroll: true %>
    #
    # @example Suppress the close button
    #   <%= tabler_ui.offcanvas "my-offcanvas", close_button: false %>
    #
    # @example Always-visible sidebar from lg upward
    #   <%= tabler_ui.offcanvas "my-offcanvas", expand: "lg" %>
    #
    # @example HTML attributes
    #   <%= tabler_ui.offcanvas "my-offcanvas", title: "Filters",
    #                           html: { class: "mb-4" },
    #                           header_html: { class: "bg-dark" },
    #                           body_html:   { data: { controller: "foo" } },
    #                           footer_html: { class: "text-end" } %>
    #
    # ## Accessibility
    #
    # The root `.offcanvas` carries `tabindex="-1"`, `role="dialog"`, and
    # either `aria-labelledby` (pointing at the `.offcanvas-title`) when a
    # title is showing, or a translated `aria-label` when it isn't. The
    # close button carries its own translated `aria-label`.
    #
    # Note: the close button lives inside `.offcanvas-header`, so the header
    # renders whenever a header slot, `title:`, or `close_button:` calls for
    # it -- not only when a header slot or `title:` is given.
    #
    # Note: the block yields exactly one argument, the SlotContext --
    # `do |slots|`, not `do |offcanvas, slots|`.
    class Component
      include TablerUi::Base

      attr_reader :id, :position, :title, :narrow, :backdrop, :scroll, :close_button, :expand

      # @param id [String] Mandatory DOM id for the `.offcanvas` root -- the
      #   anchor a caller's own toggler points at via
      #   `data-bs-toggle="offcanvas" data-bs-target="##{id}"`.
      # @param options [Hash]
      # @option options [String]  :title    Rendered as an `<h5 class="offcanvas-title">`
      #   inside the header when no `header` slot is given.
      # @option options [String, Symbol] :position Edge the panel slides in
      #   from -- one of `:start` (default), `:end`, `:top`, `:bottom`.
      #   Invalid values raise `ArgumentError`.
      # @option options [Boolean] :narrow   `offcanvas-narrow` (fixed 20rem width, default: false)
      # @option options [String, Symbol] :expand Breakpoint (`sm`/`md`/`lg`/`xl`/`xxl`) at and
      #   above which the panel becomes a permanently visible sidebar instead of a slide-in
      #   overlay. Bootstrap hides `.offcanvas-header` at that breakpoint, so the close button
      #   disappears too -- expected sidebar behaviour, not a bug. Omitted by default (always
      #   a slide-in overlay).
      # @option options [Boolean, Symbol, String] :backdrop Bootstrap's `data-bs-backdrop`
      #   option -- omitted (Bootstrap default: true), `false`, or `:static`.
      # @option options [Boolean] :scroll   Bootstrap's `data-bs-scroll` option -- allow
      #   body scrolling while the offcanvas is open (default: false)
      # @option options [Boolean] :close_button Whether to render the `.btn-close` (default: true)
      # @option options [Hash]    :html         HTML attributes for the root `.offcanvas` (part :root)
      # @option options [Hash]    :header_html  HTML attributes for the `.offcanvas-header` (part :header)
      # @option options [Hash]    :body_html    HTML attributes for the `.offcanvas-body` (part :body)
      # @option options [Hash]    :footer_html  HTML attributes for the `.offcanvas-footer` (part :footer)
      def initialize(id, options = {})
        @id = id
        @position = TablerUi::Position.validate!(options[:position] || :start, context: "offcanvas")
        @title = options[:title]
        @narrow = options[:narrow]
        @expand = TablerUi::Breakpoint.validate!(options[:expand], context: "offcanvas")
        @backdrop = options[:backdrop]
        @scroll = options[:scroll]
        @close_button = options.key?(:close_button) ? options[:close_button] : true

        initialize_html_options(options)
      end

      # @return [String] id of the rendered `.offcanvas-title`, used as the
      #   `aria-labelledby` target
      def title_id
        "#{id}-title"
      end

      # @return [String] translated aria-label for the root when no title is showing
      def dialog_label
        I18n.t("tabler_ui.offcanvas.dialog_label")
      end

      # @return [String] translated aria-label for the `.btn-close`
      def close_label
        I18n.t("tabler_ui.offcanvas.close")
      end

      # @param title_visible [Boolean] whether an `<h5 class="offcanvas-title">`
      #   with id #title_id is actually rendered this pass -- depends on
      #   whether a header slot was given, which only the template knows, so
      #   it's handed in rather than guessed here. See the class docs'
      #   Accessibility section.
      # @return [Hash] attributes for the root `.offcanvas` element (part :root)
      def root_attributes(title_visible: false)
        defaults = {
          id: id,
          class: root_classes,
          tabindex: "-1",
          role: "dialog",
          data: { controller: "tabler-ui--offcanvas" }
        }
        defaults[title_visible ? :"aria-labelledby" : :"aria-label"] =
          title_visible ? title_id : dialog_label
        defaults[:"data-bs-backdrop"] = backdrop_value if backdrop_value
        defaults[:"data-bs-scroll"] = scroll_value if scroll_value

        html_for(:root, defaults)
      end

      # @return [Hash] attributes for the `.offcanvas-header` (part :header).
      #   Unlike Modal, Bootstrap's Offcanvas markup has no dialog/content
      #   wrapper -- `.offcanvas` is both the sizing box and the flex
      #   container for its parts, so this renders one level flatter than
      #   Modal, and the close button lives inside this header rather than as
      #   a sibling of it (Tabler's CSS positions it via
      #   `.offcanvas-header .btn-close`; there's no equivalent of Modal's
      #   `.modal-content > .btn-close` override for offcanvas).
      def header_attributes
        html_for(:header, class: "offcanvas-header")
      end

      # @return [Hash] attributes for the `.offcanvas-body` (part :body)
      def body_attributes
        html_for(:body, class: "offcanvas-body")
      end

      # @return [Hash] attributes for the `.offcanvas-footer` (part :footer)
      def footer_attributes
        html_for(:footer, class: "offcanvas-footer")
      end

      private

      def root_classes
        classes = [expand ? "offcanvas-#{expand}" : "offcanvas", "offcanvas-#{position}"]
        classes << "offcanvas-narrow" if narrow
        classes.join(" ")
      end

      # @return [String, nil] the `data-bs-backdrop` value, or nil to omit
      #   the attribute entirely (Bootstrap's own default -- true -- applies)
      def backdrop_value
        return nil if backdrop.nil? || backdrop == true
        return "false" if backdrop == false

        backdrop.to_s
      end

      # @return [String, nil] the `data-bs-scroll` value, or nil to omit the
      #   attribute entirely (Bootstrap's own default -- false -- applies)
      def scroll_value
        "true" if scroll
      end
    end
  end
end
