# frozen_string_literal: true

require "ostruct"

module TablerUi
  # Core UI component dispatcher
  # Dynamically resolves component names and renders them via method_missing pattern
  class Ui
    include ActionView::Helpers::RenderingHelper
    include ActionView::Helpers::TagHelper
    include ActionView::Context

    # @param view_context [ActionView::Base] The view context where components are rendered
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
          build_legacy_component(component_class, args, kwargs)
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

    # 1. Class exists and includes TablerUi::Base — the new convention:
    # mandatory arguments positional, optional arguments in a trailing
    # `options = {}` hash. Callers still pass pure keyword syntax, so incoming
    # kwargs are split: required positional params are pulled out by name, the
    # remainder is passed through as the options hash.
    #
    # No existing component uses this path yet — it activates the first time a
    # component class is converted to `include TablerUi::Base`.
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

    # 2. Class exists but does NOT include TablerUi::Base — the old
    # long-keyword-list convention. Currently serves all 13 existing component
    # classes: Alert, Badge, DarkModeToggle, Dropdown, Icon, Illustration,
    # Navbar, Placeholder, Rating, SettingsPage, Status, Tabs, Datagrid.
    # Delete this branch (and this method) once the last one is converted to
    # TablerUi::Base.
    def build_legacy_component(component_class, args, kwargs)
      init_method = component_class.instance_method(:initialize)

      if init_method.parameters.any? { |type, _| type == :keyreq || type == :key }
        # Keyword-arg constructor, e.g. Badge#initialize(text: nil, color: nil, ...)
        component_class.new(**kwargs)
      else
        # Positional view_context constructor — only Dropdown today:
        # Dropdown#initialize(view_context), attributes injected afterwards.
        object = args.first
        object = OpenStruct.new(kwargs) if object.nil? && kwargs.any?
        object = OpenStruct.new(object) if object.is_a?(Hash)

        component = component_class.new(@view)
        inject_data(component, object) if object.present?
        component
      end
    end

    # 3. No class for this name at all — the OpenStruct fallback. Currently
    # serves the 7 bare partials: button, card, page_header, table, stat_card,
    # progress, avatar.
    def build_open_struct_component(args, kwargs)
      object = args.first
      object = OpenStruct.new(kwargs) if object.nil? && kwargs.any?
      object = OpenStruct.new(object) if object.is_a?(Hash)
      object
    end

    # --- Rendering -------------------------------------------------------------

    # Partial path depends only on whether a component class was found: both
    # the modern (TablerUi::Base) and legacy branches render the class-backed
    # partial; the OpenStruct fallback renders the bare partial. Replaces the
    # old component_class? instance-sniffing, which guessed the answer from
    # the rendered object's class name — now that build_* above already knows
    # which case we're in, that guesswork is unnecessary.
    def partial_path_for(name, component_class)
      component_class ? "tabler_ui/#{name}/component" : "tabler_ui/#{name}"
    end

    # Decides whether the block gets the component itself (builder style) or a
    # SlotContext, then captures and renders.
    def render_block(component_class, component, partial_path, name, &block)
      if component_class&.include?(TablerUi::Base)
        if component_class.builder_style?
          # Modern builder-style path (component class calls builder_style!).
          # No existing component uses this yet.
          @view.capture(component, &block)
          render_component(partial_path, name, component, nil)
        else
          # Modern slot-based path — default for TablerUi::Base components
          # that don't declare builder_style!. No existing component uses
          # this yet.
          slot_context = SlotContext.new(@view)
          @view.capture(slot_context, &block)
          render_component(partial_path, name, component, slot_context)
        end
      else
        # Legacy duck-typed sniffing, unchanged — serves all 13 legacy
        # component classes and all 7 bare partials. Builder-style among
        # these today: Navbar, Dropdown, Tabs, SettingsPage, Datagrid (they
        # respond to one of add/left/right/buttons/actions/item/tab).
        # Everything else uses SlotContext. Delete once every component is
        # converted to TablerUi::Base.
        if component.respond_to?(:add) || component.respond_to?(:left) ||
           component.respond_to?(:right) || component.respond_to?(:buttons) ||
           component.respond_to?(:actions) || component.respond_to?(:item) ||
           component.respond_to?(:tab)
          @view.capture(component, &block)
          render_component(partial_path, name, component, nil)
        else
          slot_context = SlotContext.new(@view)
          @view.capture(slot_context, &block)
          render_component(partial_path, name, component, slot_context)
        end
      end
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

    # Injects data into component instance variables
    # @param component [Object] Component instance
    # @param data [OpenStruct, Hash] Data to inject
    def inject_data(component, data)
      data.to_h.each do |key, value|
        component.public_send("#{key}=", value) if component.respond_to?("#{key}=")
      end
    end
  end

  # Slot context for content projection
  # Allows components to capture and render named content blocks
  class SlotContext
    # @param view_context [ActionView::Base] The view context
    def initialize(view_context)
      @view_context = view_context
      @slots = {}
    end

    # Captures slot content via method_missing
    # @param name [Symbol] Slot name
    # @param block [Proc] Content block to capture
    # @return [String, nil] Captured content or nil
    def method_missing(name, *args, &block)
      if block_given?
        # Capture the block content - this properly handles <%= %> outputs
        content = @view_context.capture(&block)
        @slots[name] = content
        # Return empty string to avoid output in the capture context
        ""
      else
        @slots[name]
      end
    end

    def respond_to_missing?(name, include_private = false)
      true
    end

    # Check if any slots have been defined
    # @return [Boolean]
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
