# frozen_string_literal: true

# Hand-written fixture for spec/lib/tabler_ui/docs/doc_parser_spec.rb -- NOT
# a real tabler_ui component and never loaded/required. Exercises a
# component with no doc block at all: no comment immediately above `class
# Component`, none immediately above `def initialize` either.

module TablerUi
  module FixtureUndocumented
    class Component
      def initialize(options = {})
        @options = options
      end
    end
  end
end
