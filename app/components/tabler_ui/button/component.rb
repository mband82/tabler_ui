# frozen_string_literal: true

module TablerUi
  module Button
    # Button component for Tabler UI. Renders a Bootstrap/Tabler styled
    # `<a>` (via `link_to`) when `method:` is the default `:get`, or a
    # `<form>`/`<button>` (via `button_to`) for any other HTTP method --
    # unless `turbo: true` is given, in which case a non-GET method also
    # renders as a plain `<a>` (see #turbo_link? and "Turbo" below).
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
    #
    # @example Confirmation dialog
    #   <%= tabler_ui.button text: "Delete", color: "danger", url: "/widgets/1", method: :delete,
    #                        confirm: "Are you sure?" %>
    #
    # @example Non-GET action as a Turbo link, no nested <form>
    #   <%= tabler_ui.button text: "Delete", color: "danger", url: "/widgets/1", method: :delete,
    #                        turbo: true %>
    #
    # ## Turbo
    #
    # As with `table`/`pagination`'s `frame:`, the gem takes no `turbo-rails`
    # dependency here -- it only emits Turbo-flavoured markup. Both `confirm:`
    # and `turbo:` are inert without Turbo loaded in the host app.
    #
    # `confirm:` renders `data-turbo-confirm="<string>"` on whichever element
    # this component renders (the `<a>` in the `method: :get` branch, or the
    # `<button>` inside the `button_to`-generated form otherwise). This is
    # read by Turbo, NOT by the old rails-ujs `data-confirm` -- the gem never
    # emits `data-confirm`. Without Turbo loaded, `data-turbo-confirm` does
    # nothing at all; the action fires unconfirmed.
    #
    # `turbo:` (default `false`) only changes anything when the method is
    # non-GET. `button_to` wraps its `<button>` in a `<form>` -- a `<form>`
    # nested inside another `<form>` (an edit form with a delete button, for
    # example) is invalid HTML that browsers silently mangle. `turbo: true`
    # sidesteps that: instead of a form, it renders a plain
    # `<a href="...">` carrying `data-turbo-method="<verb>"`, exactly like
    # Turbo's own idiomatic non-GET link. No `<form>` is emitted. This needs
    # Turbo loaded to actually perform the non-GET request -- without it, the
    # link just GETs the URL like any other `<a href>`.
    #
    # `turbo: true` combined with `method: :get` (the default) is a no-op --
    # the method is already rendered as a plain `<a>`, so there is nothing
    # non-GET to convert. It does not raise.
    class Component
      include TablerUi::Base

      attr_reader :text, :color, :outline, :size, :shape, :icon_only, :url,
                  :http_method, :target, :title, :disabled, :icon, :action,
                  :loading, :floating, :animate_icon, :ghost, :confirm, :turbo

      ANIMATE_ICON_MODIFIERS = %w[rotate shake tada pulse move-start].freeze

      # @param options [Hash]
      # @option options [String]  :text        Button label
      # @option options [String]  :color       Color variant -- validated against
      #   TablerUi::Color (Tabler palette + Bootstrap semantic names), plus the brand
      #   and muted colours ("github", "x", "muted", ...), which only buttons accept.
      #   Defaults to "primary".
      # @option options [Boolean] :outline     Outline variant, i.e. "btn-outline-<color>" (default: false)
      # @option options [String, Symbol] :size Button size, rendered as "btn-<size>"
      # @option options [String]  :shape       "pill" (btn-pill) or "square" (btn-square)
      # @option options [Boolean] :icon_only   Icon-only style, i.e. "btn-icon" (default: false)
      # @option options [Boolean] :action      Action button style -- transparent/compact/hover-highlight
      #   ("btn-action"), replacing the color/outline/shape/icon_only classes (default: false)
      # @option options [Boolean] :loading     Loading style ("btn-loading"). The CSS only sets
      #   `pointer-events: none` -- it does not disable the element, so pass `disabled: true` too
      #   if the button must also be unfocusable/non-activatable (default: false)
      # @option options [Boolean] :floating    Fixed-position floating style ("btn-floating") (default: false)
      # @option options [Boolean, String] :animate_icon Animates the icon on hover/focus
      #   ("btn-animate-icon"). `true` for the base slide animation, or one of
      #   "rotate", "shake", "tada", "pulse", "move-start" for that modifier
      #   ("btn-animate-icon-<x>"). Modifiers do not compose -- only one at a time.
      # @option options [Boolean] :ghost       Ghost style, appends "btn-ghost" alongside
      #   "btn-<color>" (default: false). Tabler defines no outline+ghost combination, so this
      #   raises ArgumentError if combined with outline: true.
      # @option options [String]  :url         URL for the button (default: "#")
      # @option options [Symbol, String] :method HTTP method. :get (default) renders `link_to`;
      #   any other value renders `button_to`.
      # @option options [String]  :target      Rendered as target="..."
      # @option options [String]  :title       Rendered as title="..."
      # @option options [Boolean] :disabled    Rendered as disabled="..."
      # @option options [Hash]    :data        Data attributes, merged with the html: hook's :data
      # @option options [String]  :icon        Tabler icon name, rendered before the text
      # @option options [String]  :confirm     Confirmation prompt -- renders as
      #   `data-turbo-confirm="..."`, merged with :data/html:'s :data rather than
      #   clobbering them. See "Turbo" above for what this needs to actually work.
      # @option options [Boolean] :turbo       Render a non-GET action as a Turbo link
      #   (`<a data-turbo-method="...">`) instead of `button_to`'s `<form>`. No-op when
      #   method: is :get (default: false). See "Turbo" above.
      # @option options [Hash]    :html        Rule 5 HTML hook for the root <a>/<button> (part :root)
      def initialize(options = {})
        @action = options[:action]
        @text = options.key?(:text) ? options[:text] : default_text
        @color = TablerUi::Color.validate!(options[:color],
                                            extra: TablerUi::Color::BRAND + TablerUi::Color::MUTED,
                                            context: "button") || "primary"
        @outline = options[:outline]
        @size = options[:size]
        @shape = options[:shape]
        @icon_only = options[:icon_only]
        @loading = options[:loading]
        @floating = options[:floating]
        @animate_icon = validate_animate_icon!(options[:animate_icon])
        @ghost = options[:ghost]
        @url = options[:url].presence || "#"
        @http_method = options[:method] || :get
        @target = options[:target]
        @title = options[:title]
        @disabled = options[:disabled]
        @data = options[:data]
        @icon = options[:icon]
        @confirm = options[:confirm]
        @turbo = options[:turbo] || false

        raise ArgumentError, "ghost: true cannot be combined with outline: true -- " \
                              "Tabler defines no outline+ghost combination" if @ghost && @outline

        initialize_html_options(options)
      end

      # @return [Boolean] whether the button renders via `link_to` (true) or `button_to`/#turbo_link? (false)
      def get?
        @http_method.to_s == "get"
      end

      # @return [Boolean] whether a non-GET action renders as a Turbo link
      #   (`<a data-turbo-method="...">`, no <form>) rather than `button_to`.
      #   Always false for method: :get -- see the class docs' "Turbo" section.
      def turbo_link?
        @turbo && !get?
      end

      # @return [Boolean] whether the root element renders as `<a>` -- either
      #   the plain method: :get case, or a non-GET action rendered via
      #   #turbo_link?. The ERB dispatches on this rather than repeating
      #   `get? || turbo_link?` itself.
      def link?
        get? || turbo_link?
      end

      # @return [Boolean] whether the button has an icon to render before its text
      def has_icon?
        @icon.present?
      end

      # @return [Hash] attributes for the root <a>/<button> (part :root),
      #   merged with whatever the caller supplied via html:. Does not
      #   include a literal :method key -- callers rendering via `button_to`
      #   add that themselves, since it would otherwise leak onto `link_to`
      #   as a literal method="..." HTML attribute. #turbo_link?'s verb is
      #   carried instead as data-turbo-method, inside :data -- see #root_data.
      def root_attributes
        defaults = {
          class: button_classes,
          target: @target,
          title: @title,
          disabled: @disabled
        }
        defaults[:data] = root_data if root_data.present?

        html_for(:root, defaults)
      end

      private

      # @return [Hash] the :data hash for #root_attributes -- the caller's
      #   own :data option, plus data-turbo-confirm (when :confirm was
      #   given) and data-turbo-method (when #turbo_link?). Built here,
      #   rather than merged in a second step on top of #root_attributes'
      #   result, so TablerUi::HtmlOptions.merge_html only ever sees one
      #   :data hash on our side and merges it against the html: hook's
      #   :data exactly once -- see rule 5.
      def root_data
        data = @data ? @data.dup : {}
        data[:turbo_confirm] = @confirm if @confirm.present?
        data[:turbo_method] = @http_method if turbo_link?
        data
      end

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
          (@icon_only ? "btn-icon" : nil),
          (@loading ? "btn-loading" : nil),
          (@floating ? "btn-floating" : nil),
          (@ghost ? "btn-ghost" : nil),
          *animate_icon_classes
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
        when "pill" then "btn-pill"
        when "square" then "btn-square"
        end
      end

      def animate_icon_classes
        return [] unless @animate_icon

        return ["btn-animate-icon"] if @animate_icon == true

        ["btn-animate-icon", "btn-animate-icon-#{@animate_icon}"]
      end

      # Returns the validated animate_icon value (true, a modifier String, or nil),
      # or raises ArgumentError naming the offender and the valid values.
      def validate_animate_icon!(value)
        return nil if value.nil? || value == false
        return true if value == true

        value = value.to_s
        return value if ANIMATE_ICON_MODIFIERS.include?(value)

        raise ArgumentError, "unknown animate_icon #{value.inspect} for button — " \
                              "valid: true, #{ANIMATE_ICON_MODIFIERS.join(', ')}"
      end
    end
  end
end
