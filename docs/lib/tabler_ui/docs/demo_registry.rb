# frozen_string_literal: true

module TablerUi
  module Docs
    # In-memory registry of every Demo, built up by docs/lib/tabler_ui/docs/demos/*_demos.rb
    # calling `DemoRegistry.define(:component) { |c| c.demo ... }` at load time.
    # See docs/DEMOS.md for the full contract; this is the implementation.
    module DemoRegistry
      # Raised by Builder#demo when an id is reused within one component, or
      # when two demos (even in different components) would collide on slug.
      class DuplicateDemoError < StandardError; end

      # Yielded to a demos file's `define` block. Not meant to be
      # instantiated directly -- `DemoRegistry.define` is the entry point.
      class Builder
        def initialize(component)
          @component = component
        end

        # @param id [Symbol] unique within this component
        # @param title [String] human-facing description, WITHOUT the
        #   component name -- the demo already lives under its component, so
        #   a title of "colors, light, pill" is correct, not "badge - colors, ...".
        # @param source [String] ERB, from a single-quoted heredoc (<<~'ERB').
        #   See docs/DEMOS.md ("Why .rb, not .erb") for why single-quoted.
        # @param locals [Proc, nil] see Demo#resolved_locals
        def demo(id, title:, source:, locals: nil)
          DemoRegistry.register(Demo.new(id, @component, title: title, source: source, locals: locals))
        end
      end

      class << self
        # Entry point for a demos file: TablerUi::Docs::DemoRegistry.define(:badge) { |c| ... }
        def define(component)
          yield Builder.new(component.to_sym)
        end

        # @api private -- called by Builder#demo. Not part of the public DSL.
        def register(demo)
          registry.fetch(demo.component, []).each do |existing|
            if existing.id == demo.id
              raise DuplicateDemoError, "duplicate demo id :#{demo.id} for component :#{demo.component}"
            end
          end

          if all.any? { |existing| existing.slug == demo.slug }
            raise DuplicateDemoError, "duplicate demo slug #{demo.slug.inspect}"
          end

          (registry[demo.component] ||= []) << demo
        end

        # @return [Array<Demo>] every registered demo, across every component
        def all
          registry.values.flatten
        end

        # @return [Array<Demo>] the demos registered for one component, in
        #   registration order. Empty array for an unknown component -- never raises.
        def for(component)
          registry[component.to_sym] || []
        end

        # @return [Demo, nil] the demo with this slug, or nil
        def find(slug)
          all.find { |demo| demo.slug == slug.to_s }
        end

        # @return [Array<Symbol>] every component with at least one registered demo
        def components
          registry.keys
        end

        # Requires every docs/lib/tabler_ui/docs/demos/*_demos.rb file exactly
        # once. Safe to call more than once -- each file is loaded with
        # `require` (not `load`), so Ruby's own $LOADED_FEATURES tracking is
        # what makes a second call a no-op; nothing here re-checks that.
        # Called once at gem-load time by docs/lib/tabler_ui/docs.rb. See
        # docs/DEMOS.md ("Where demo files get loaded").
        def load_demos!
          Dir[File.join(__dir__, "demos", "*.rb")].sort.each { |file| require file }
        end

        private

        def registry
          @registry ||= {}
        end
      end
    end
  end
end
