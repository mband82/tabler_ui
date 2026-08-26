# frozen_string_literal: true

require "tabler_ui/docs/parsed_component"

module TablerUi
  module Docs
    # Turns a component's `# frozen_string_literal: true` + doc-comment
    # source into a ParsedComponent the docs engine can render.
    #
    # No YARD. YARD is not a dependency of this gem today, and pulling in a
    # full doc framework just to walk two comment blocks per component is
    # disproportionate for a gem that ships into production apps. This is a
    # focused line scanner for exactly the two conventions this codebase
    # already uses (see any component under app/components/tabler_ui/):
    #
    #   1. A `#` comment block immediately above `class Component` -- free
    #      prose, `## Heading` / `### Sub-heading` sections, `@example
    #      <title>` blocks.
    #   2. A `#` comment block immediately above `def initialize` --
    #      `@param`/`@option options [Type] :name  description` rows, with
    #      continuation lines indented deeper than the `@option` line they
    #      belong to.
    #
    # The two blocks are NOT purely "prose here, options there" -- a
    # component is free to keep documenting itself (more `##`/`###`
    # sections, more `@example`s) in the block above `def initialize`,
    # after its `@option` list, and several real components do (see
    # table's "## Sorting"/"## Filtering"/"## Turbo Frames", which live in
    # exactly that block, not the one above `class Component`). So both
    # blocks are scanned by the same #scan_block state machine for
    # sections/examples/options; only `description` is deliberately taken
    # from the class-level block alone (see ParsedComponent and #parse_file).
    #
    # Parsing is plain `File.readlines` plus regexes on comment text -- none
    # of the ERB-scanner hazards elsewhere in this project apply, since
    # there is no markup to tokenize, just `#`-prefixed Ruby comment lines.
    #
    # This parser must NEVER raise on a component whose comments don't
    # follow the convention -- #parse_file rescues broadly and returns an
    # empty ParsedComponent instead, so a docs page can render a
    # placeholder rather than blowing up the whole site over one
    # under-documented component.
    #
    # ## Caching
    #
    # .all memoizes its result in a class-level Hash, keyed by component
    # name, alongside each source file's mtime at parse time (@cache in
    # this file). Every call re-checks each file's current mtime against
    # the cached one and only re-parses when it has changed, so:
    #
    # * In production, where component source never changes at runtime,
    #   every file is parsed exactly once per process.
    # * In Rails development -- where docs/lib is NOT on the main engine's
    #   autoload/reload paths (see docs/lib/tabler_ui/docs/engine.rb's own
    #   comment on why it has to live outside the gem's ordinary autoload
    #   tree), this module itself is never reloaded by Zeitwerk between
    #   requests. The mtime check is what keeps its *output* fresh anyway:
    #   editing a component's doc comment and reloading the docs page picks
    #   up the change immediately, without a server restart, because the
    #   changed file's mtime no longer matches the cached one. Unchanged
    #   components are not needlessly re-read off disk on every request.
    #
    # #parse_file itself is a pure function of a path -- it does no
    # caching and can be called directly (as the spec's fixture and
    # coverage-sweep examples do) without touching or warming the cache.
    module DocParser
      # Matches a `#`-comment line, capturing everything after the line's
      # FIRST `#`. Used with #match (never #gsub) so a literal `#` later in
      # a comment's own text (e.g. describing a CSS selector like
      # `#header`) is left alone -- only the line's leading `#` is
      # structural.
      COMMENT_LINE = /\A\s*#(.*)\z/.freeze

      CLASS_LINE = /\Aclass\s+Component\b/.freeze
      INITIALIZE_LINE = /\Adef\s+initialize\b/.freeze

      # Built via Regexp.new from a single-quoted string, not a regex
      # literal -- `#{2,3}` inside a `/.../ ` literal is parsed by Ruby as
      # string interpolation (`#{...}`) before the regex engine ever sees
      # it, which is a SyntaxError for the non-expression `2,3`. A
      # single-quoted String never interpolates, so `#{2,3}` reaches the
      # regex engine unchanged, where it's the ordinary quantifier syntax
      # for "the literal `#` character, 2 to 3 times".
      HEADING = Regexp.new('\A(#{2,3})\s+(.+)\z').freeze
      EXAMPLE = /\A@example\b\s*(.*)\z/.freeze
      OPTION = /\A@option\s+options\s+\[([^\]]+)\]\s+:(\S+)(?:\s+(.*))?\z/.freeze
      TAG_LINE = /\A@\S/.freeze
      BLANK_LINE = /\A\s*\z/.freeze
      INDENTED_LINE = /\A\s+\S/.freeze

      # Used only by .builder_options / #each_builder_def below -- matches
      # (against the already-`lstrip`ped line, like every anchor above)
      # any `def`, a `class`/`module` opener capturing its name, or a bare
      # `end`. Comment lines never match any of the three: they start with
      # `#` after lstrip, not `d`/`c`/`m`/`e`.
      DEF_LINE = /\Adef\s+([a-zA-Z_]\w*[?!]?)/.freeze
      NESTING_LINE = /\A(class|module)\s+([A-Za-z_][\w:]*)/.freeze
      END_LINE = /\Aend\s*\z/.freeze

      class << self
        # @return [Array<String>] absolute paths to every component.rb
        #   under app/components/tabler_ui/*/component.rb -- there is no
        #   separate component registry; this walk IS the source of truth
        #   for "what components exist" (mirrors how the dispatcher itself,
        #   lib/tabler_ui/ui.rb, has no registry either).
        def component_paths
          Dir[TablerUi::Engine.root.join("app/components/tabler_ui/*/component.rb")].sort
        end

        # @return [Hash{String => ParsedComponent}] every component, keyed
        #   by name, memoized -- see the "Caching" section above.
        def all
          @cache ||= {}

          component_paths.each_with_object({}) do |path, result|
            name = component_name(path)
            result[name] = cached_parse(path, name)
          end
        end

        # @param name [String] a component name, e.g. "table"
        # @return [ParsedComponent, nil] that component's parsed docs, or
        #   nil if no such component exists
        def find(name)
          all[name.to_s]
        end

        # Recovers @option rows documented on a builder-style component's
        # sub-item methods (NavigationGroup#add, DropDownProxy#item,
        # Tabs#tab, ...) -- rows #parse_file never sees, since its
        # #comment_block_above(lines, INITIALIZE_LINE) call only ever
        # reaches the *first* `def initialize` in the file (the top-level
        # Component's). Purely additive: does not touch, and is never
        # consulted by, #parse_file or the .all/.find cache -- see the
        # "Caching" section above for why this keeps its own
        # @builder_cache instead of sharing @cache.
        #
        # @param name [String] a component name, e.g. "navbar"
        # @return [Hash{String => Hash{String => Array<ParsedComponent::Option>}}]
        #   options keyed first by the enclosing class name -- there can be
        #   more than one per component (navbar defines `divider` on both
        #   NavigationGroup and DropDownProxy; collapsing that to a flat
        #   method-name key would silently merge two unrelated methods'
        #   options), then by method name. {} for an unknown component, or
        #   one with no builder sub-methods carrying @option rows. Never
        #   raises.
        def builder_options(name)
          path = component_paths.find { |p| component_name(p) == name.to_s }
          return {} unless path

          cached_builder_options(path)
        end

        # Drops the memoized cache. Not needed for normal operation (the
        # mtime check already keeps .all fresh) -- exists for specs that
        # want a clean slate.
        def reset!
          @cache = {}
          @builder_cache = {}
        end

        # Parses a single component.rb. Pure function of +path+: no
        # caching, never raises -- a file with unrecognisable or absent
        # doc comments yields a ParsedComponent with a nil description and
        # empty collections rather than an error.
        #
        # @param path [String] absolute path to a component.rb
        # @return [ParsedComponent]
        def parse_file(path)
          name = component_name(path)
          lines = File.readlines(path, chomp: true)

          class_result = scan_block(comment_block_above(lines, CLASS_LINE))
          init_result = scan_block(comment_block_above(lines, INITIALIZE_LINE))

          ParsedComponent.new(
            name,
            description: class_result[:description],
            sections: class_result[:sections] + init_result[:sections],
            examples: class_result[:examples] + init_result[:examples],
            options: class_result[:options] + init_result[:options]
          )
        rescue StandardError
          ParsedComponent.new(component_name(path))
        end

        private

        def component_name(path)
          File.basename(File.dirname(path))
        end

        def cached_parse(path, name)
          mtime = File.mtime(path)
          cached = @cache[name]
          return cached[:parsed] if cached && cached[:mtime] == mtime

          parsed = parse_file(path)
          @cache[name] = { mtime: mtime, parsed: parsed }
          parsed
        rescue Errno::ENOENT
          # File vanished between the Dir[] glob and here (e.g. a
          # concurrent delete) -- treat like any other unparseable
          # component rather than raising.
          ParsedComponent.new(name)
        end

        # Same mtime-keyed memoization as #cached_parse, in a separate
        # @builder_cache so a bug in this brand-new path can never corrupt
        # or invalidate @cache (or vice versa).
        def cached_builder_options(path)
          @builder_cache ||= {}
          name = component_name(path)
          mtime = File.mtime(path)
          cached = @builder_cache[name]
          return cached[:parsed] if cached && cached[:mtime] == mtime

          parsed = parse_builder_options(path)
          @builder_cache[name] = { mtime: mtime, parsed: parsed }
          parsed
        rescue Errno::ENOENT
          {}
        end

        # Pure function of +path+, like #parse_file -- never raises. Walks
        # the file once (#each_builder_def), and for every `def` other
        # than `initialize` whose comment block yields at least one
        # @option row -- run through the very same #scan_block state
        # machine #parse_file uses, per the module doc's warning against a
        # second comment-grammar parser -- records those options under the
        # method's enclosing class name and its own name.
        def parse_builder_options(path)
          lines = File.readlines(path, chomp: true)
          result = {}

          each_builder_def(lines) do |class_name, method_name, def_index|
            next if method_name == "initialize"

            options = scan_block(comment_block_above(lines, DEF_LINE, start: def_index))[:options]
            next if options.empty?

            (result[class_name] ||= {})[method_name] = options
          end

          result
        rescue StandardError
          {}
        end

        # Walks +lines+ tracking class/module nesting by indentation, and
        # yields [enclosing_class_name, method_name, line_index] for every
        # `def` found inside some `class`. A `def` with no enclosing class
        # (never happens for a real component.rb, which always sits inside
        # at least `module TablerUi; module X; class Component`) is
        # skipped rather than yielded with a nil name.
        #
        # Indentation-based, not a real Ruby parser -- reliable here only
        # because this codebase is uniformly 2-space indented (CLAUDE.md
        # rule 4's neighbourhood) and rubocop-free files still follow it.
        # A construct's `end` always sits at the same indentation as the
        # line that opened it, and everything nested inside is indented
        # strictly deeper than that -- so matching a bare `end` line's
        # indentation against the indentation the top-of-stack frame was
        # *opened* at is enough to know that `end` closes that frame, and
        # not some more deeply nested class/module/def/if/block whose own
        # `end` merely happens to come first.
        def each_builder_def(lines)
          stack = []

          lines.each_with_index do |line, index|
            indent = line[/\A */].length
            stripped = line.lstrip

            if (match = NESTING_LINE.match(stripped))
              stack.push(kind: match[1], name: match[2], indent: indent)
            elsif END_LINE.match?(stripped) && stack.last && stack.last[:indent] == indent
              stack.pop
            elsif (match = DEF_LINE.match(stripped))
              enclosing = stack.reverse_each.find { |frame| frame[:kind] == "class" }
              yield(enclosing[:name], match[1], index) if enclosing
            end
          end
        end

        # Walks upward from the line immediately above the first line at
        # index +start+ or later matching +anchor+, collecting contiguous
        # `#`-comment lines into their content (the text after the line's
        # first `#`, with exactly one conventional leading space stripped
        # so deeper-indented continuation lines keep their relative
        # indentation). Stops at the first line that isn't a comment
        # (blank line or code) -- for a real component that non-comment
        # line is the module/class nesting it always sits inside, so the
        # walk naturally stops at the block's true start.
        #
        # +start:+ defaults to 0, so #parse_file's two call sites (each
        # still passing only +lines+ and +anchor+) get exactly the same
        # first-match to end-of-file search, hence the same result, as
        # before this parameter existed. .builder_options is what needs
        # +start:+: it calls this once per `def` occurrence, seeding
        # +start+ with that occurrence's own line index so each call finds
        # that exact `def` (DEF_LINE matches any `def`) rather than
        # re-finding the first one in the file every time.
        #
        # @return [Array<String>] the block's lines, in source order, or
        #   [] when +anchor+ isn't found at or after +start+, or has no
        #   comment block above it
        def comment_block_above(lines, anchor, start: 0)
          anchor_index = (start...lines.length).find { |i| anchor.match?(lines[i].lstrip) }
          return [] unless anchor_index

          raw = []
          i = anchor_index - 1
          while i >= 0
            match = COMMENT_LINE.match(lines[i])
            break unless match

            raw.unshift(strip_one_leading_space(match[1]))
            i -= 1
          end
          raw
        end

        def strip_one_leading_space(content)
          content.start_with?(" ") ? content[1..] : content
        end

        # Single state machine over one comment block's lines, recognising
        # `## `/`### ` headings, `@example` blocks, `@option options
        # [Type] :name` rows (with indented continuation lines folded in),
        # and everything else (only at the very start of the block, before
        # any of the above) as leading description prose.
        #
        # Any other `@tag` (`@param`, `@return`, ...) ends whatever was
        # currently accumulating and is otherwise ignored -- it plays no
        # part in the extracted structure, but recognising it stops its
        # own indented continuation (if any) from being mis-attributed to
        # a section body or an option description.
        #
        # @return [Hash] :description (String, nil), :sections
        #   (Array<ParsedComponent::Section>), :examples
        #   (Array<ParsedComponent::Example>), :options
        #   (Array<ParsedComponent::Option>)
        def scan_block(lines)
          state = {
            description_lines: [], sections: [], examples: [], options: [],
            section: nil, example: nil, option: nil, mode: :prose, description_open: true
          }

          lines.each { |line| scan_line(state, line) }
          flush_section(state)
          flush_example(state)

          {
            description: join_prose(state[:description_lines]),
            sections: state[:sections],
            examples: state[:examples],
            options: state[:options]
          }
        end

        def scan_line(state, line)
          if (match = HEADING.match(line))
            start_section(state, match)
          elsif (match = EXAMPLE.match(line))
            start_example(state, match)
          elsif (match = OPTION.match(line))
            start_option(state, match)
          elsif TAG_LINE.match?(line)
            close_current(state, next_mode: :ignored)
          elsif BLANK_LINE.match?(line)
            scan_blank_line(state)
          elsif state[:mode] == :option && INDENTED_LINE.match?(line)
            state[:option].description = "#{state[:option].description} #{line.strip}".strip
          else
            scan_content_line(state, line)
          end
        end

        def start_section(state, match)
          flush_section(state)
          flush_example(state)
          close_current(state, next_mode: :section)
          state[:section] = { title: match[2].strip, level: match[1].length, body: [] }
        end

        def start_example(state, match)
          flush_example(state)
          flush_section(state)
          close_current(state, next_mode: :example)
          state[:example] = { title: match[1].strip.presence, code: [] }
        end

        def start_option(state, match)
          flush_section(state)
          flush_example(state)
          state[:description_open] = false
          state[:mode] = :option
          state[:option] = ParsedComponent::Option.new(match[2], match[1], match[3].to_s)
          state[:options] << state[:option]
        end

        # Ends whatever construct is currently open (without touching
        # sections/examples, already flushed by the caller when relevant)
        # and marks description prose as closed -- once anything
        # structured has been seen, later "bare" lines are never folded
        # back into the leading description.
        def close_current(state, next_mode:)
          state[:option] = nil
          state[:description_open] = false
          state[:mode] = next_mode
        end

        def scan_blank_line(state)
          case state[:mode]
          when :section then state[:section][:body] << ""
          when :example then state[:example][:code] << ""
          when :option
            state[:option] = nil
            state[:mode] = state[:description_open] ? :prose : :ignored
          when :prose
            state[:description_lines] << "" if state[:description_open]
          end
        end

        def scan_content_line(state, line)
          case state[:mode]
          when :section then state[:section][:body] << line
          when :example then state[:example][:code] << line
          when :prose
            state[:description_lines] << line if state[:description_open]
          when :option
            # Non-indented, non-tag, non-blank content while an option was
            # open: not a continuation (those are indented) -- conventions
            # never produce this, but rather than mis-attribute it, treat
            # the option as closed and drop the line.
            state[:option] = nil
            state[:mode] = :ignored
          end
        end

        def flush_section(state)
          section = state[:section]
          return unless section

          state[:sections] << ParsedComponent::Section.new(section[:title], section[:level], join_prose(section[:body]))
          state[:section] = nil
        end

        def flush_example(state)
          example = state[:example]
          return unless example

          state[:examples] << ParsedComponent::Example.new(example[:title], dedent(example[:code]))
          state[:example] = nil
        end

        # Joins comment-block lines into prose: blank comment lines become
        # paragraph breaks, everything else is kept verbatim (including
        # its own indentation, for bullet lists like table's "##
        # Filtering" section). Leading/trailing blank lines are trimmed.
        # Returns nil for an empty/blank block.
        def join_prose(lines)
          lines.join("\n").strip.presence
        end

        # Strips the smallest common leading whitespace off every
        # non-blank code line, and trims leading/trailing blank lines --
        # purely cosmetic dedenting for display; the code itself is
        # otherwise untouched (still verbatim, see ParsedComponent).
        def dedent(lines)
          trimmed = lines.drop_while(&:blank?)
          trimmed = trimmed.reverse.drop_while(&:blank?).reverse
          return "" if trimmed.empty?

          indent = trimmed.reject(&:blank?).map { |l| l[/\A */].length }.min || 0
          trimmed.map { |l| l.blank? ? "" : l[indent..] }.join("\n")
        end
      end
    end
  end
end
