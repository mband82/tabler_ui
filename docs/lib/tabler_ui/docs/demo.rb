# frozen_string_literal: true

module TablerUi
  module Docs
    # A single runnable documentation example: one ERB string that is both
    # rendered live (via `render inline:`, see docs/app/views/tabler_ui/docs/demos/_demo.html.erb)
    # and printed, escaped, as its own code sample. See docs/DEMOS.md for the
    # full contract -- this class only holds the data.
    #
    # Never instantiate directly. Demo files under
    # docs/lib/tabler_ui/docs/demos/*_demos.rb build these through
    # DemoRegistry.define's block (`c.demo ...`), which is the only supported
    # way to register one.
    class Demo
      attr_reader :id, :component, :title, :source, :locals

      # @param id [Symbol] unique within `component`
      # @param component [Symbol] the tabler_ui.<component> this demo belongs to
      # @param title [String] human-facing description of what the demo shows
      # @param source [String] the ERB source, rendered verbatim and printed verbatim
      # @param locals [Proc, nil] zero-arg proc returning a Hash of locals for
      #   `source` to reference. See docs/DEMOS.md ("Stateful demos: locals:").
      def initialize(id, component, title:, source:, locals: nil)
        @id = id.to_sym
        @component = component.to_sym
        @title = title
        @source = source
        @locals = locals
      end

      # Globally-unique identifier for anchors/search: "<component>-<id>".
      # DemoRegistry enforces this is unique across every registered demo,
      # not just within one component.
      def slug
        "#{component}-#{id}"
      end

      # The Hash `source` is rendered with. `locals` is only ever called here,
      # lazily, once per render -- never at registration time -- so a Proc
      # that builds fresh objects (e.g. an ActiveRecord-less struct standing
      # in for state) gets a fresh value on every render.
      def resolved_locals
        locals ? locals.call : {}
      end
    end
  end
end
