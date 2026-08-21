# frozen_string_literal: true

module TablerUi
  module Docs
    # Structured result of parsing one component's doc comments -- see
    # DocParser for how these get built. A plain value object: no behaviour
    # beyond reading the fields back, so the rendering side (a future docs
    # page/template) stays dumb and this stays trivially testable in
    # isolation.
    #
    # `examples` are ILLUSTRATIVE ONLY. They are Ruby comments lifted
    # verbatim off real component source -- e.g. table's @example blocks
    # reference `User.all`, `users_path`, `@pagy.page`, none of which exist
    # anywhere in this codebase. They exist to be displayed as inert,
    # syntax-highlighted code on the docs page. Do NOT render them through
    # ERB, `eval`, or any other execution path -- there is nothing backing
    # those calls, and "executing the docs" is not a feature anyone asked
    # for.
    class ParsedComponent
      # One `## `/`### ` section from the class-level doc block.
      #
      # @!attribute title
      #   @return [String] heading text, with the `#`/`##` marker stripped
      # @!attribute level
      #   @return [Integer] 2 for `##`, 3 for `###`
      # @!attribute body
      #   @return [String] the section's prose, verbatim (markdown-ish,
      #     un-rendered)
      Section = Struct.new(:title, :level, :body)

      # One `@example` block from the class-level doc block.
      #
      # @!attribute title
      #   @return [String, nil] the text after `@example` on its own line,
      #     or nil when the block carried no title (`@example` alone)
      # @!attribute code
      #   @return [String] the example's code, verbatim (dedented), for
      #     display only -- see the class docs above
      Example = Struct.new(:title, :code)

      # One `@option options [Type] :name description` row from the
      # `initialize` doc block, continuation lines folded in.
      #
      # @!attribute name
      #   @return [String] the option key, without its leading `:`
      # @!attribute type
      #   @return [String] the YARD-style type tag content, e.g. "Boolean",
      #     "String, Symbol"
      # @!attribute description
      #   @return [String] the option's description, with any indented
      #     continuation lines folded into a single, space-joined string
      Option = Struct.new(:name, :type, :description)

      attr_reader :name, :description, :sections, :examples, :options

      # @param name [String] the component's directory name, e.g. "table"
      # @param options [Hash]
      # @option options [String, nil] :description
      # @option options [Array<Section>] :sections (default: [])
      # @option options [Array<Example>] :examples (default: [])
      # @option options [Array<Option>] :options (default: [])
      def initialize(name, options = {})
        @name = name
        @description = options[:description]
        @sections = options[:sections] || []
        @examples = options[:examples] || []
        @options = options[:options] || []
      end

      # @return [Boolean] whether anything at all was recognised -- false
      #   for a component with no parseable doc comments, so the docs page
      #   can render a placeholder instead of an empty-looking page.
      def documented?
        description.present? || sections.any? || examples.any? || @options.any?
      end
    end
  end
end
