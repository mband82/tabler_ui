# frozen_string_literal: true

# Hand-written fixture for spec/lib/tabler_ui/docs/doc_parser_spec.rb -- NOT
# a real tabler_ui component and never loaded/required. Locks DocParser's
# behaviour against comment shapes independently of whatever any real
# component's comments currently say, so a wording tweak on a real
# component can never accidentally change what this spec is proving.
#
# Exercises: multi-line @option continuations, an @example with no title, a
# ### heading nested under a ##, and an @option whose description contains
# a literal # character.

module TablerUi
  module FixtureFull
    # Fixture component exercising the doc parser's full feature set.
    #
    # Some leading description prose that spans
    # more than one line, forming a paragraph.
    #
    # A second paragraph, after a blank comment line.
    #
    # @example
    #   <%= tabler_ui.fixture_full %>
    #
    # @example With options
    #   <%= tabler_ui.fixture_full color: "primary" %>
    #
    # ## Top Section
    #
    # Prose that belongs to the top-level section.
    #
    # ### Nested Subsection
    #
    # Prose that belongs to the nested subsection, distinguishable by its
    # level rather than by physical nesting.
    class Component
      # @param options [Hash]
      # @option options [String] :color Base color, validated against a fixed
      #   palette. Continuation line one, testing multi-line @option
      #   handling across more than one extra line of indented text.
      # @option options [String] :selector CSS selector like "#header", tests a literal # character embedded in text.
      # @option options [Hash] :html Rule 5 HTML hook for the root element
      def initialize(options = {})
        @color = options[:color]
        @selector = options[:selector]
      end
    end
  end
end
