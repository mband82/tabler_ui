# frozen_string_literal: true

require "ostruct"

module TablerUi
  # Core UI component dispatcher
  # Dynamically resolves component names and renders them via method_missing pattern
  class Ui
    include ActionView::Helpers::RenderingHelper
    include ActionView::Helpers::TagHelper
    include ActionView::Context

    def initialize(view_context)
      @view = view_context
    end

    # Dynamically handles component method calls
    # Converts component_name to TablerUi::ComponentName::Component class
    # Falls back to rendering partials if no component class exists
    #
    # @param name [Symbol] The component name (e.g., :navbar, :page_header)
    # @param args [Array] Arguments passed to the component
    # @param kwargs [Hash] Keyword arguments converted to component attributes
    # @param block [Proc] Optional block for content projection and slots
    # @return [String] Rendered HTML output
    def method_missing(name, *args, **kwargs, &block)
      klass_name = "TablerUi::#{name.to_s.camelize}::Component"
      component_class = klass_name.safe_constantize

      component =
        if component_class&.include?(TablerUi::Base)
          build_modern_component(component_class, name, args, kwargs)
        elsif component_class
          raise ArgumentError,
                "#{component_class} must `include TablerUi::Base` to be rendered by tabler_ui.#{name}"
        else
          build_open_struct_component(args, kwargs)
        end

      partial_path = partial_path_for(name, component_class)

      if block
        render_block(component_class, component, partial_path, name, &block)
      else
        render_component(partial_path, name, component)
      end
    end

    def respond_to_missing?(name, include_private = false)
      true
    end

    private

    # --- Component construction ---------------------------------------------

    # 1. Class exists and includes TablerUi::Base — the convention every
    # shipped component now follows: mandatory arguments positional, optional
    # arguments in a trailing `options = {}` hash. Callers still pass pure
    # keyword syntax, so incoming kwargs are split: required positional params
    # are pulled out by name, the remainder is passed through as the options
    # hash.
    def build_modern_component(component_class, name, args, kwargs)
      # Caller passed real positional args (rare) — honour them directly.
      return component_class.new(*args, kwargs) if args.any?

      required = component_class.instance_method(:initialize).parameters
                                 .select { |type, _| type == :req }
                                 .map(&:last)

      positional = required.map do |key|
        kwargs.fetch(key) { raise ArgumentError, "tabler_ui.#{name} requires #{key}:" }
      end

      component_class.new(*positional, kwargs.except(*required))
    end

    # 2. No class for this name at all — the OpenStruct fallback. Every
    # component shipped by this gem is now class-backed, but this stays as a
    # supported extension point: a host app can drop its own
    # app/components/tabler_ui/_thing.html.erb into its tree (the engine
    # prepends the host's view path) and call tabler_ui.thing(...) without
    # writing a component class.
    def build_open_struct_component(args, kwargs)
      object = args.first
      object = OpenStruct.new(kwargs) if object.nil? && kwargs.any?
      object = OpenStruct.new(object) if object.is_a?(Hash)
      object
    end

    # --- Rendering -------------------------------------------------------------

    # A class-backed component renders tabler_ui/<name>/component; the
    # OpenStruct fallback renders the bare tabler_ui/_<name> partial.
    def partial_path_for(name, component_class)
      component_class ? "tabler_ui/#{name}/component" : "tabler_ui/#{name}"
    end

    # Decides whether the block gets the component itself (builder style) or a
    # SlotContext, then captures and renders.
    #
    # Builder style is declared, not guessed: a component calls `builder_style!`
    # in its class body. This replaced duck-typing on a fixed allowlist of
    # method names (add/left/right/buttons/actions/item/tab), where a component
    # defining `item` for an unrelated reason silently flipped block styles.
    def render_block(component_class, component, partial_path, name, &block)
      if component_class&.builder_style?
        @view.capture(component, &block)
        # Builder components only know their full item list once the block has
        # run, so anything that validates across items (steps' current: index)
        # can't check in initialize. Give them a hook here, before rendering --
        # raising inside the template instead would get wrapped in
        # ActionView::Template::Error, burying the real message in #cause.
        component.validate! if component.respond_to?(:validate!)
        render_component(partial_path, name, component, nil)
      else
        # Slot style: the default for components, and the only option for
        # OpenStruct-backed bare partials.
        slot_context = SlotContext.new(@view)
        captured = @view.capture(slot_context, &block)
        guard_discarded_block!(name, captured, slot_context)
        render_component(partial_path, name, component, slot_context)
      end
    end

    # A slot component's block only has an effect through `slots.<name> { }`
    # calls -- whatever the block itself emits is captured and thrown away.
    # So this renders nothing at all, with no error:
    #
    #   <%= tabler_ui.card title: "x" do %>Body text<% end %>
    #
    # The content is right here in `captured`, so instead of discarding it
    # silently, say what happened.
    def guard_discarded_block!(name, captured, slot_context)
      return unless slot_context.empty?
      return if captured.blank?

      raise ArgumentError,
            "tabler_ui.#{name}'s block wrote content but set no slots, so it would render " \
            "nothing. Put it in a slot: `do |slots| slots.body { ... } end`."
    end

    # Renders the component partial with appropriate locals
    # @param partial_path [String] Partial path to render
    # @param name [Symbol] Component name
    # @param component [Object] Component instance or OpenStruct
    # @param slots [SlotContext, nil] Optional slot context for content projection
    # @return [String] Rendered HTML
    def render_component(partial_path, name, component, slots = nil)
      if slots
        @view.render(partial_path, name => component, slots: slots)
      else
        @view.render(partial_path, name => component)
      end
    end

  end

  # Slot context for content projection
  # Allows components to capture and render named content blocks
  class SlotContext
    def initialize(view_context)
      @view_context = view_context
      @slots = {}
    end

    # @param name [Symbol] Slot name
    # @param block [Proc] Content block to capture
    # @return [String, nil] Captured content or nil
    def method_missing(name, *args, &block)
      if block_given?
        # Capture the block content - this properly handles <%= %> outputs
        content = @view_context.capture(&block)
        @slots[name] = content
        ""
      else
        @slots[name]
      end
    end

    def respond_to_missing?(name, include_private = false)
      true
    end

    # @return [Boolean] whether any slots have been defined
    def empty?
      @slots.empty?
    end

    # Check if a specific slot has content
    def present?(name = nil)
      if name
        @slots[name].present?
      else
        @slots.values.any?(&:present?)
      end
    end
  end
end
