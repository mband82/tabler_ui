# frozen_string_literal: true

require_relative "contract"
require_relative "slot_map"
require_relative "builder_map"
require_relative "enum_map"
require "tabler_ui/docs/navigation"
require "tabler_ui/docs/doc_parser"

module TablerUi
  module Docs
    module Editor
      # Validates and normalizes one design tree (see Contract's "Node kinds"
      # section) against a raw, untrusted payload.
      #
      # ## Security boundary
      #
      # `raw_node` is whatever the design-editor's save/preview endpoint
      # received in a request body -- attacker-controlled, arbitrarily
      # shaped, arbitrarily deep. #call NEVER raises on it: a hostile or
      # malformed payload always comes back as a Result with errors, never
      # an exception. The only things that may raise out of this class are
      # genuine programmer errors in this file itself (and even those are
      # caught by a last-resort rescue in .call, converted to a fatal
      # Result, so a bug here degrades to "reject the tree" rather than
      # "crash the request").
      #
      # Everything downstream -- Renderer (tree -> HTML) and ErbGenerator
      # (tree -> .html.erb) -- trusts `Result#node` completely and performs
      # NO validation of its own. That is the whole point of this class: it
      # is the one and only place a hostile payload gets checked, so every
      # invariant either module relies on (real component names, allowlisted
      # HTML attributes, no `auth:`, bounded nesting) must be true of
      # `Result#node` by construction. If it turns out a rule needs
      # strengthening, it gets strengthened here -- never patched around
      # downstream.
      #
      # ## What "normalized" means
      #
      # - Every key that survives is one Contract already describes for that
      #   node kind. Unknown keys are gone.
      # - Component option values are coerced toward their documented type
      #   where that can be determined (EnumMap for enums, the @option
      #   doc block's YARD type tag for Boolean/Integer) and enum values
      #   matching EnumMap.symbol? are real Symbols, not Strings.
      # - No default is ever written in. An option a caller omitted stays
      #   omitted -- the component applies its own default at render time,
      #   and writing it here would make the exported ERB spell out options
      #   nobody asked for.
      #
      # ## What happens to an invalid node
      #
      # The contract doesn't define an "error" node kind, and downstream
      # can't be handed a kind it doesn't know about, so an invalid node is
      # never *replaced* -- it is dropped from wherever it sat (a `children`
      # array, a slot, an `items` array) and the reason is recorded in
      # `Result#errors`. Its siblings still normalize. `Result#fatal?`
      # (`#node` is nil) is reserved for the tree as a whole being
      # unusable: `raw_node` isn't even a Hash, or the root node's own
      # `kind`/`id` don't check out. A design with one bad node still comes
      # back as a valid, slightly smaller tree plus a loud error -- full
      # rejection of an otherwise-fine multi-hour design over one bad leaf
      # would be a worse failure mode than that.
      #
      # `Result#errors` is one flat Array of human-readable Strings, not
      # split into errors vs. warnings -- the contract only specifies that
      # single field. A dropped-but-not-fatal issue (an unrecognised option
      # key, a truncated string) is still recorded, prefixed "warning:" so a
      # caller that wants to distinguish severity can, but every message is
      # meant to be readable on its own either way.
      class Tree
        # @!attribute node
        #   @return [Hash, nil] the normalized tree, or nil if the tree as a
        #     whole is unusable (see class docs -- "What happens to an
        #     invalid node")
        # @!attribute errors
        #   @return [Array<String>] every problem found, in the order
        #     encountered
        Result = Struct.new(:node, :errors) do
          def fatal?
            node.nil?
          end
        end

        # Kinds allowed at the very root of a call. `fragment` only ever
        # appears here (see Contract: "fragment root only") -- a nested
        # fragment is rejected the same way `builder_item` is rejected
        # everywhere except inside an `items` array. `column` is excluded
        # too: rule 9 requires a column's *parent* to literally be a `row`,
        # and the root has no parent at all.
        ROOT_KINDS = %w[fragment row heading text component partial].freeze

        # Kinds allowed as a direct child of `fragment` or `column` (and as
        # the contents of a slot, and of a builder_item's `children` block)
        # -- everything ordinary except `column` itself, which rule 9 only
        # allows directly under a `row`.
        NON_ROW_CONTAINER_KINDS = %w[row heading text component partial].freeze

        # Kinds allowed as a direct child of `row` -- `column` is legal
        # here (this IS the row rule 9 requires), but a second `row` is
        # not ("a row may not be a direct child of a row").
        ROW_CONTAINER_KINDS = %w[column heading text component partial].freeze

        # Depth guard for sanitizing an arbitrary option/attribute *value*
        # (as opposed to tree *node* nesting, which Contract::LIMITS[:depth]
        # governs). A legitimate option value is a flat scalar or, at most,
        # a one- or two-level Hash (table's `sort:`/`filter:`) -- this bound
        # only exists so a hostile deeply-nested Hash handed to some option
        # can't make the sanitizer itself recurse unboundedly. Not part of
        # Contract because it has nothing to do with tree shape.
        SANITIZE_MAX_DEPTH = 6

        # @param raw_node the untrusted payload for one design tree (see
        #   Contract's "Node kinds" section for the intended shape --
        #   anything else is handled, never raised on)
        # @return [Result]
        def self.call(raw_node)
          new.call(raw_node)
        end

        def call(raw_node)
          @errors = []
          @seen_ids = {}
          @counter = { count: 0, limit_reported: false }

          node = normalize(raw_node, path: "root", depth: 1, allowed_kinds: ROOT_KINDS)
          Result.new(node, @errors)
        rescue StandardError => e
          # Last-resort net -- see the class docs' "Security boundary"
          # section. Every real code path above is written to degrade to
          # an error message instead of raising; this only catches a bug
          # in that code, and still returns a fatal Result rather than
          # letting the exception escape to the caller.
          Result.new(nil, (@errors || []) + ["internal error: #{e.class}: #{e.message}"])
        end

        private

        # --- Dispatch ------------------------------------------------------

        # Every node, of every kind, passes through here exactly once. This
        # is where the rules that apply to ALL kinds live: the global node
        # budget, kind membership, structural placement (`allowed_kinds`),
        # depth, and id shape/uniqueness. Kind-specific rules live in the
        # `normalize_<kind>` methods this dispatches to.
        def normalize(raw, path:, depth:, allowed_kinds:, builder_context: nil)
          return drop_over_node_limit if node_limit_reached?

          @counter[:count] += 1

          unless raw.is_a?(Hash)
            add_error("#{path}: expected an object, got #{raw.class}")
            return nil
          end

          raw = stringify_keys(raw)
          kind = raw["kind"]

          unless kind.is_a?(String) && Contract::KINDS.include?(kind)
            add_error("#{path}: missing or unrecognised kind #{kind.inspect}")
            return nil
          end

          unless allowed_kinds.include?(kind)
            add_error("#{path}: '#{kind}' is not allowed here")
            return nil
          end

          if depth > Contract::LIMITS[:depth]
            add_error("#{path}: exceeds the maximum nesting depth (#{Contract::LIMITS[:depth]})")
            return nil
          end

          id = raw["id"]
          unless id.is_a?(String) && Contract::NODE_ID.match?(id)
            add_error("#{path}: invalid or missing id #{id.inspect}")
            return nil
          end

          if @seen_ids.key?(id)
            add_error("#{path}: duplicate id #{id.inspect} (already used at #{@seen_ids[id]})")
            return nil
          end
          @seen_ids[id] = path

          dispatch(kind, raw, id, path, depth, builder_context)
        end

        def dispatch(kind, raw, id, path, depth, builder_context)
          case kind
          when "fragment" then normalize_fragment(raw, id, path, depth)
          when "row" then normalize_row(raw, id, path, depth)
          when "column" then normalize_column(raw, id, path, depth)
          when "heading" then normalize_heading(raw, id, path)
          when "text" then normalize_text(raw, id, path)
          when "component" then normalize_component(raw, id, path, depth)
          when "partial" then normalize_partial(raw, id, path)
          when "builder_item" then normalize_builder_item(raw, id, path, depth, builder_context)
          end
        end

        # --- Global node budget ---------------------------------------------

        def node_limit_reached?
          @counter[:count] >= Contract::LIMITS[:nodes]
        end

        # Reported exactly once, however many nodes are left unprocessed --
        # a hostile payload with a million siblings must not produce a
        # million-line error array.
        def drop_over_node_limit
          unless @counter[:limit_reported]
            add_error("tree exceeds the maximum of #{Contract::LIMITS[:nodes]} nodes; the rest were dropped")
            @counter[:limit_reported] = true
          end
          nil
        end

        # --- Container kinds -------------------------------------------------

        def normalize_fragment(raw, id, path, depth)
          {
            "kind" => "fragment",
            "id" => id,
            "children" => normalize_children(raw["children"], path: "#{path}.children", depth: depth,
                                                                allowed_kinds: NON_ROW_CONTAINER_KINDS)
          }
        end

        def normalize_row(raw, id, path, depth)
          {
            "kind" => "row",
            "id" => id,
            "attrs" => normalize_attrs(raw["attrs"], path: "#{path}.attrs"),
            "children" => normalize_children(raw["children"], path: "#{path}.children", depth: depth,
                                                                allowed_kinds: ROW_CONTAINER_KINDS)
          }
        end

        # Reaching this method at all already proves the column sits
        # directly under a row -- `normalize`'s `allowed_kinds` gate is what
        # enforces rule 9, so there is nothing left to re-check here.
        def normalize_column(raw, id, path, depth)
          {
            "kind" => "column",
            "id" => id,
            "span" => normalize_span(raw["span"], path: "#{path}.span"),
            "attrs" => normalize_attrs(raw["attrs"], path: "#{path}.attrs"),
            "children" => normalize_children(raw["children"], path: "#{path}.children", depth: depth,
                                                                allowed_kinds: NON_ROW_CONTAINER_KINDS)
          }
        end

        def normalize_children(raw_children, path:, depth:, allowed_kinds:)
          arr = as_capped_array(raw_children, path: path, limit: Contract::LIMITS[:children_per_node])

          out = []
          arr.each_with_index do |child, i|
            if node_limit_reached?
              drop_over_node_limit
              break
            end

            normalized = normalize(child, path: "#{path}[#{i}]", depth: depth + 1, allowed_kinds: allowed_kinds)
            out << normalized if normalized
          end
          out
        end

        # --- Static-content kinds --------------------------------------------

        def normalize_heading(raw, id, path)
          level = coerce_heading_level(raw["level"])
          unless level && Contract::HEADING_LEVELS.include?(level)
            add_error("#{path}: heading level must be one of #{Contract::HEADING_LEVELS.to_a.join(', ')}, " \
                       "got #{raw['level'].inspect}")
            return nil
          end

          content = normalize_required_content(raw["content"], path: "#{path}.content")
          return nil if content.nil?

          { "kind" => "heading", "id" => id, "level" => level, "content" => content }
        end

        def normalize_text(raw, id, path)
          tag = raw["tag"]
          unless tag.is_a?(String) && Contract::TEXT_TAGS.include?(tag)
            add_error("#{path}: text tag must be one of #{Contract::TEXT_TAGS.join(', ')}, got #{tag.inspect}")
            return nil
          end

          content = normalize_required_content(raw["content"], path: "#{path}.content")
          return nil if content.nil?

          { "kind" => "text", "id" => id, "tag" => tag, "content" => content }
        end

        # A little leniency for a stringified level ("3") from a sloppy
        # client -- not a security concern either way, since the result is
        # still checked against HEADING_LEVELS immediately after.
        def coerce_heading_level(value)
          return value if value.is_a?(Integer)
          return value.to_i if value.is_a?(String) && value.match?(/\A[1-6]\z/)

          nil
        end

        # Returns the sanitized String, or nil (with an error already
        # recorded) if +value+ isn't usable at all -- distinct from
        # #sanitize_generic_value because content is mandatory here: there
        # is no "drop the key and move on", the whole node goes.
        def normalize_required_content(value, path:)
          unless value.is_a?(String)
            add_error("#{path}: must be a string, got #{value.class}")
            return nil
          end

          if Contract::DANGEROUS_VALUE.match?(value)
            add_error("#{path}: rejected (matches a dangerous value pattern)")
            return nil
          end

          if value.length > Contract::LIMITS[:string]
            add_warning("#{path}: truncated to #{Contract::LIMITS[:string]} characters")
            return value[0, Contract::LIMITS[:string]]
          end

          value
        end

        # --- partial -----------------------------------------------------------

        def normalize_partial(raw, id, path)
          value = raw["path"]
          unless value.is_a?(String)
            add_error("#{path}.path: must be a string, got #{value.class}")
            return nil
          end

          normalized = validate_partial_path(value, path: "#{path}.path")
          return nil unless normalized

          { "kind" => "partial", "id" => id, "path" => normalized }
        end

        def validate_partial_path(value, path:)
          unless value.end_with?(Contract::PATH_SUFFIX) && !value.start_with?("/")
            add_error("#{path}: must end with #{Contract::PATH_SUFFIX} and not start with '/' -- got #{value.inspect}")
            return nil
          end

          base = value.delete_suffix(Contract::PATH_SUFFIX)
          segments = base.split("/", -1)

          if segments.length > Contract::MAX_PATH_SEGMENTS
            add_error("#{path}: more than #{Contract::MAX_PATH_SEGMENTS} path segments")
            return nil
          end

          unless segments.any? && segments.all? { |s| Contract::PATH_SEGMENT.match?(s) }
            add_error("#{path}: contains an empty, '.', '..', or otherwise invalid segment -- got #{value.inspect}")
            return nil
          end

          value
        end

        # --- component -----------------------------------------------------------

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def normalize_component(raw, id, path, depth)
          name = raw["name"]
          unless valid_component_name?(name)
            add_error("#{path}: unknown or invalid component name #{name.inspect}")
            return nil
          end

          # Safe only because `name` just passed the Navigation.components
          # allowlist above -- see Contract::COMPONENT_NAME's own comment on
          # why the allowlist, not the regex, is the real control here.
          klass = "TablerUi::#{name.camelize}::Component".safe_constantize
          unless klass
            add_error("#{path}: component '#{name}' has no Component class")
            return nil
          end

          args_out = normalize_component_args(klass, raw["args"], name: name, path: path)
          return nil unless args_out

          meta = component_option_metadata(name)
          options_out = normalize_options(raw["options"], meta: meta, owner: "component '#{name}'", path: path)
          normalize_declarative_columns(options_out, name: name, path: path)
          normalize_declarative_sort_url(options_out, name: name, path: path)
          guard_sort_requires_sort_url(options_out, name: name, path: path)
          html_out = normalize_html(raw["html"], allowed_parts: meta[:html_parts], path: "#{path}.html")

          result = { "kind" => "component", "id" => id, "name" => name, "args" => args_out,
                     "options" => options_out, "html" => html_out }

          if builder_style?(klass)
            if raw["slots"]
              add_error("#{path}.slots: not valid on builder-style component '#{name}' -- use items instead")
            end
            result["items"] = normalize_items(raw["items"], component: name, level: :root,
                                                              path: "#{path}.items", depth: depth)
          else
            if raw["items"]
              add_error("#{path}.items: not valid on slot-style component '#{name}' -- use slots instead")
            end
            result["slots"] = normalize_slots(raw["slots"], component: name, path: "#{path}.slots", depth: depth)
          end

          result
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        def valid_component_name?(name)
          name.is_a?(String) && Contract::COMPONENT_NAME.match?(name) && Navigation.components.include?(name)
        end

        # table's real :columns wants a `value:` Proc per column, which JSON
        # cannot carry, so a design tree declares `key:` instead and both
        # Renderer and ErbGenerator build the callable from it (see
        # Renderer#synthesize_table_columns). A column with neither is the one
        # shape those two disagree on: Renderer isolates it into an inline
        # marker, ErbGenerator raises, and a raise reaches the preview
        # endpoint as a failed request rather than a rendered design. Rejecting
        # it here, once, is what keeps the two downstream walkers on trees they
        # both accept -- the same reason every other cross-module invariant
        # lives in this class rather than in either of them.
        #
        # Reused below by #normalize_declarative_sort_url and
        # #guard_sort_requires_sort_url -- :sort_url is table's OTHER
        # declarative-instead-of-callable option, and is scoped to the same
        # set of components for the same reason.
        DECLARATIVE_COLUMN_COMPONENTS = %w[table].freeze

        def normalize_declarative_columns(options, name:, path:)
          return unless DECLARATIVE_COLUMN_COMPONENTS.include?(name)

          columns = options["columns"]
          return unless columns.is_a?(Array)

          kept = columns.reject.with_index do |column, index|
            missing = !column.is_a?(Hash) || (column["key"].nil? && column["value"].nil?)
            add_error("#{path}.options.columns[#{index}]: needs a key: naming the row field to display") if missing
            missing
          end

          if kept.empty?
            options.delete("columns")
          else
            options["columns"] = kept
          end
        end

        # table's real :sort_url wants a callable too (`sort_url.call(key,
        # dir)`) -- JSON cannot carry one, so a design tree carries a
        # declarative Hash instead (see SortUrl's own doc for both modes)
        # and Renderer#synthesize_sort_url / ErbGenerator#format_sort_url_value
        # each build the real lambda from it, independently, via the same
        # SortUrl.pattern_for conversion. This method validates only the
        # declarative Hash's SHAPE -- mode is one of the two known values,
        # simple mode carries all three of its string fields, pattern
        # mode's pattern actually varies by both key and dir -- and drops
        # it (reporting why) when that shape is wrong, the same "drop and
        # report, don't fail the whole tree" contract #normalize_declarative_columns
        # already applies to :columns. It does NOT itself convert simple
        # mode to a pattern -- that conversion happens once, in
        # SortUrl.pattern_for, so there is exactly one place a future
        # change to the simple-mode formula needs to land (see that
        # module's doc for the whole story).
        def normalize_declarative_sort_url(options, name:, path:)
          return unless DECLARATIVE_COLUMN_COMPONENTS.include?(name)

          sort_url = options["sort_url"]
          return if sort_url.nil?

          options.delete("sort_url") unless valid_declarative_sort_url?(sort_url, path: "#{path}.options.sort_url")
        end

        def valid_declarative_sort_url?(value, path:)
          unless value.is_a?(Hash)
            add_error("#{path}: must be an object carrying a mode:, got #{value.class}")
            return false
          end

          case value["mode"]
          when "simple" then valid_simple_sort_url?(value, path: path)
          when "pattern" then valid_pattern_sort_url?(value, path: path)
          else
            add_error("#{path}.mode: must be 'simple' or 'pattern', got #{value['mode'].inspect}")
            false
          end
        end

        # All three fields are required -- a simple-mode sort_url missing
        # any one of them has no way to build a working per-column,
        # per-direction URL, so it is rejected wholesale rather than
        # partially honored. Every missing/blank field is reported, not
        # just the first one, so a caller fixing this doesn't have to
        # resubmit repeatedly to discover the next problem.
        def valid_simple_sort_url?(value, path:)
          ok = true
          %w[path sortParam dirParam].each do |key|
            next if value[key].is_a?(String) && !value[key].empty?

            add_error("#{path}.#{key}: simple sort_url needs a non-empty string #{key}")
            ok = false
          end
          ok
        end

        # A pattern that never varies by key or dir (e.g. a hardcoded
        # "/users?sort=name") is a silently broken sort UI -- every column
        # would link to the exact same href, so clicking a header would
        # never actually change the sort. Requiring both placeholders to
        # appear at least once is the cheapest check that catches that
        # without trying to parse the pattern as a real URL template.
        def valid_pattern_sort_url?(value, path:)
          pattern = value["pattern"]
          unless pattern.is_a?(String)
            add_error("#{path}.pattern: must be a string, got #{pattern.class}")
            return false
          end

          ok = pattern.include?("{key}") && pattern.include?("{dir}")
          add_error("#{path}.pattern: must contain both {key} and {dir} placeholders, got #{pattern.inspect}") unless ok
          ok
        end

        # A column's `sort:` is only meaningful alongside the table's own
        # `sort_url:`, which Table::Component#guard_sort_url! makes
        # mandatory the moment any column carries one -- reaching that
        # guard with none configured (never set, or dropped just above for
        # failing shape validation) would blow the whole node up into an
        # inline error marker at render time, and raise outright from
        # ErbGenerator (see Renderer's error-isolation doc). Catching it
        # here instead keeps the same "drop the offending piece, report
        # why, everything else still renders" contract every other
        # validation failure in this class gets: only the dangling `sort:`
        # is dropped from each affected column -- its `label:`/`key:`
        # and every other column are untouched, so the table itself still
        # renders, just without a sortable header on that one column.
        def guard_sort_requires_sort_url(options, name:, path:)
          return unless DECLARATIVE_COLUMN_COMPONENTS.include?(name)
          return if options.key?("sort_url")

          columns = options["columns"]
          return unless columns.is_a?(Array)

          columns.each_with_index do |column, index|
            next unless column.is_a?(Hash) && !column["sort"].nil?

            add_error("#{path}.options.columns[#{index}].sort: dropped -- add the table's own sort_url: " \
                       "before making a column sortable")
            column.delete("sort")
          end
        end

        # Defensive against a future component whose class somehow doesn't
        # include TablerUi::Base (the real dispatcher, lib/tabler_ui/ui.rb,
        # raises on that instead -- this one must not raise on anything).
        def builder_style?(klass)
          klass.respond_to?(:builder_style?) && klass.builder_style?
        end

        # @return [Hash, nil] "arg name => sanitized value" for the
        #   component's required positionals, or nil (with an error already
        #   recorded) if a required arg is missing or its value had to be
        #   rejected outright.
        def normalize_component_args(klass, raw_args, name:, path:)
          required = klass.instance_method(:initialize).parameters
                          .select { |type, _| type == :req }
                          .map { |_, pname| pname.to_s }

          normalize_required_args(stringify_keys(raw_args), required, path: path) do |missing|
            add_error("#{path}: component '#{name}' is missing required arg(s): #{missing.join(', ')}")
          end
        end

        # Shared by components and builder_items: pulls exactly the
        # required key(s) out of a raw args Hash, sanitizes each value, and
        # warns about (but doesn't fail on) anything extra. Yields the
        # missing-keys Array so each caller can phrase its own error --
        # the two read differently ("component 'x' is missing..." vs.
        # "builder item 'add' is missing...").
        def normalize_required_args(raw_args, required_keys, path:)
          missing = required_keys - raw_args.keys
          unless missing.empty?
            yield missing
            return nil
          end

          extra = raw_args.keys - required_keys
          forbidden, extra = extra.partition { |key| Contract::FORBIDDEN_OPTIONS.include?(key) }
          forbidden.each do |key|
            add_error("#{path}.args.#{key}: forbidden option stripped -- 'auth' is never allowed in a design tree")
          end
          add_warning("#{path}.args: dropped unrecognised key(s) #{extra.join(', ')}") if extra.any?

          out = {}
          required_keys.each do |key|
            raw_value = raw_args[key]
            sanitized = sanitize_generic_value(raw_value, path: "#{path}.args.#{key}")
            if sanitized.nil? && !raw_value.nil?
              add_error("#{path}.args.#{key}: value rejected, so this node cannot render")
              return nil
            end
            out[key] = sanitized
          end
          out
        end

        # @param meta [Hash] from #component_option_metadata / #builder_option_metadata
        # @param owner [String] human label for error text, e.g. "component 'card'"
        def normalize_options(raw_options, meta:, owner:, path:)
          raw_options = as_capped_hash(raw_options, path: "#{path}.options", limit: Contract::LIMITS[:options_per_node])

          out = {}
          raw_options.each do |key, value|
            if Contract::FORBIDDEN_OPTIONS.include?(key)
              add_error("#{path}.options.#{key}: forbidden option stripped -- #{owner} may not set 'auth' " \
                         "from a design tree (see Contract's note on why)")
              next
            end

            option = meta[:by_name][key]
            unless option
              add_warning("#{path}.options.#{key}: unknown option on #{owner}, dropped")
              next
            end

            sanitized = sanitize_option_value(meta[:enum_scope], option, value, path: "#{path}.options.#{key}")
            out[key] = sanitized unless sanitized.nil?
          end
          out
        end

        # @return [Hash] :by_name (option name => DocParser::ParsedComponent::Option),
        #   :html_parts (Array<String> of legal `html` keys), :enum_scope
        #   (the component name EnumMap.values_for/#symbol? should look
        #   PER_COMPONENT entries up under)
        def component_option_metadata(name)
          meta = option_metadata(DocParser.find(name)&.options || [])
          # Every component calls initialize_html_options, which maps a
          # bare "html" key to the :root part unconditionally (see
          # TablerUi::Base) -- that's a structural guarantee independent of
          # whether the doc comment happens to mention :html explicitly.
          meta[:html_parts] = (meta[:html_parts] + ["root"]).uniq
          meta[:enum_scope] = name
          meta
        end

        # DocParser.builder_options keys its outer Hash by the *bare*
        # enclosing class name ("DropDownProxy"), not the dotted path
        # BuilderMap's own `klass:` field records ("Component::NavigationGroup::
        # DropDownProxy") -- see doc_parser_spec.rb's ".builder_options"
        # examples. `.split("::").last` bridges the two vocabularies.
        #
        # Per-item html hooks (`:html`, `:link_html`, ...) are hand-rolled
        # per builder method, not the automatic initialize_html_options
        # mapping component-level options get -- so, unlike
        # #component_option_metadata, "root" is only legal here when the
        # method's own @option rows actually document a bare `:html`.
        def builder_option_metadata(component, klass, method_name)
          bare_klass = klass.to_s.split("::").last
          options = DocParser.builder_options(component).dig(bare_klass, method_name) || []
          meta = option_metadata(options)
          meta[:enum_scope] = nil
          meta
        end

        def option_metadata(options)
          html_parts = options.map(&:name).select { |n| n == "html" || n.end_with?("_html") }
                               .map { |n| n == "html" ? "root" : n.delete_suffix("_html") }

          { by_name: options.each_with_object({}) { |o, h| h[o.name] = o }, html_parts: html_parts }
        end

        # @param enum_scope [String, nil] component name to look up
        #   EnumMap entries under, or nil for a builder_item's own options
        #   (EnumMap only covers top-level component options -- see its own
        #   "Deliberately excluded" note on nested/per-item option enums
        #   being a separate concern)
        def sanitize_option_value(enum_scope, option, value, path:)
          if enum_scope && (enum_values = EnumMap.values_for(enum_scope, option.name))
            unless enum_values.include?(value.to_s)
              add_warning("#{path}: #{value.inspect} is not a valid '#{option.name}', dropped")
              return nil
            end
            return EnumMap.symbol?(enum_scope, option.name) ? value.to_s.to_sym : value.to_s
          end

          sanitize_generic_value(coerce_by_type(value, option.type), path: path)
        end

        # Best-effort coercion toward the @option doc block's YARD-style
        # type tag, applied only when the incoming value is unambiguous
        # (a numeric string for an "Integer" tag, "true"/"false" for a
        # "Boolean" one). Never guesses on an ambiguous tag ("String,
        # Symbol") -- an uncoercible value passes through unchanged and is
        # still subject to #sanitize_generic_value's own checks.
        def coerce_by_type(value, type)
          return value unless type.is_a?(String)

          if type.match?(/\bInteger\b/) && value.is_a?(String) && value.match?(/\A-?\d+\z/)
            value.to_i
          elsif type.match?(/\bBoolean\b/) && value.is_a?(String) && %w[true false].include?(value)
            value == "true"
          else
            value
          end
        end

        def normalize_html(raw_html, allowed_parts:, path:)
          raw_html = stringify_keys(raw_html)

          out = {}
          raw_html.each do |part, attrs|
            unless allowed_parts.include?(part)
              add_warning("#{path}.#{part}: unknown html part, dropped")
              next
            end
            out[part] = normalize_attrs(attrs, path: "#{path}.#{part}")
          end
          out
        end

        # --- attrs / span (row, column, and html: parts) ------------------------

        def normalize_attrs(raw_attrs, path:)
          raw_attrs = as_capped_hash(raw_attrs, path: path, limit: Contract::LIMITS[:options_per_node])

          out = {}
          raw_attrs.each do |key, value|
            if Contract::FORBIDDEN_OPTIONS.include?(key)
              add_error("#{path}.#{key}: forbidden option stripped -- 'auth' is never allowed in a design tree")
              next
            end

            if Contract::ATTR_DENY.include?(key.downcase) || Contract::ATTR_DENY_PATTERN.match?(key)
              add_error("#{path}.#{key}: attribute key is not allowed")
              next
            end

            if Contract::ATTR_NESTED_KEYS.include?(key)
              out[key] = normalize_nested_attrs(value, path: "#{path}.#{key}")
            elsif Contract::ATTR_KEYS.include?(key) || Contract::ATTR_PREFIXES.any? { |p| key.start_with?(p) }
              sanitized = sanitize_attr_value(value, path: "#{path}.#{key}")
              out[key] = sanitized unless sanitized.nil?
            else
              add_warning("#{path}.#{key}: unknown attribute key, dropped")
            end
          end
          out
        end

        # `data:`/`aria:`'s own inner keys aren't attribute names in their
        # own right (the wrapper is what stamps the "data-"/"aria-" prefix
        # on render) so ATTR_KEYS/ATTR_DENY don't apply to them -- only a
        # sane identifier shape and the same value rules as any other attr.
        def normalize_nested_attrs(value, path:)
          nested = stringify_keys(value)

          nested.each_with_object({}) do |(key, val), out|
            if Contract::FORBIDDEN_OPTIONS.include?(key)
              add_error("#{path}.#{key}: forbidden option stripped -- 'auth' is never allowed in a design tree")
              next
            end

            unless key.match?(/\A[a-zA-Z][a-zA-Z0-9_-]*\z/)
              add_warning("#{path}.#{key}: not a valid nested attribute key, dropped")
              next
            end
            sanitized = sanitize_attr_value(val, path: "#{path}.#{key}")
            out[key] = sanitized unless sanitized.nil?
          end
        end

        def sanitize_attr_value(value, path:)
          case value
          when String
            if Contract::DANGEROUS_VALUE.match?(value)
              add_error("#{path}: rejected (matches a dangerous value pattern)")
              return nil
            end
            if value.length > Contract::LIMITS[:attr_string]
              add_warning("#{path}: truncated to #{Contract::LIMITS[:attr_string]} characters")
              return value[0, Contract::LIMITS[:attr_string]]
            end
            value
          when true, false, Integer
            value
          else
            add_warning("#{path}: attribute values must be a String, Boolean or Integer -- got #{value.class}, dropped")
            nil
          end
        end

        def normalize_span(raw_span, path:)
          raw_span = stringify_keys(raw_span)

          raw_span.each_with_object({}) do |(key, value), out|
            unless Contract::SPAN_KEYS.include?(key)
              add_warning("#{path}.#{key}: unknown span key, dropped")
              next
            end

            coerced = value.is_a?(String) && value.match?(/\A\d+\z/) ? value.to_i : value
            unless Contract::SPAN_VALUES.include?(coerced)
              add_warning("#{path}.#{key}: #{value.inspect} is not a valid span value, dropped")
              next
            end
            out[key] = coerced
          end
        end

        # --- slots / items -------------------------------------------------------

        def normalize_slots(raw_slots, component:, path:, depth:)
          raw_slots = stringify_keys(raw_slots)
          legal = SlotMap.slots_for(component)

          raw_slots.each_with_object({}) do |(slot_name, nodes), out|
            unless legal.include?(slot_name)
              add_warning("#{path}.#{slot_name}: unknown slot on '#{component}', dropped")
              next
            end
            out[slot_name] = normalize_children(nodes, path: "#{path}.#{slot_name}", depth: depth,
                                                         allowed_kinds: NON_ROW_CONTAINER_KINDS)
          end
        end

        def normalize_items(raw_items, component:, level:, path:, depth:)
          arr = as_capped_array(raw_items, path: path, limit: Contract::LIMITS[:children_per_node])
          methods_map = BuilderMap.methods_for(component, level)

          out = []
          arr.each_with_index do |raw_item, i|
            if node_limit_reached?
              drop_over_node_limit
              break
            end

            normalized = normalize(raw_item, path: "#{path}[#{i}]", depth: depth + 1, allowed_kinds: %w[builder_item],
                                              builder_context: { component: component, level: level,
                                                                  methods_map: methods_map })
            out << normalized if normalized
          end
          out
        end

        # --- builder_item -------------------------------------------------------

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def normalize_builder_item(raw, id, path, depth, builder_context)
          component = builder_context[:component]
          level = builder_context[:level]
          method_name = raw["method"]
          descriptor = method_name.is_a?(String) ? builder_context[:methods_map][method_name] : nil

          unless descriptor
            add_error("#{path}: '#{method_name.inspect}' is not a legal builder method for '#{component}' " \
                       "at level #{level}")
            return nil
          end

          args_out = normalize_builder_item_args(descriptor, raw["args"], method_name: method_name, path: path)
          return nil unless args_out

          meta = builder_option_metadata(component, descriptor[:klass], method_name)
          options_out = normalize_options(raw["options"], meta: meta,
                                                            owner: "#{component}##{method_name}", path: path)
          html_out = normalize_html(raw["html"], allowed_parts: meta[:html_parts], path: "#{path}.html")

          result = { "kind" => "builder_item", "id" => id, "method" => method_name, "args" => args_out,
                     "options" => options_out, "html" => html_out }

          case descriptor[:block]
          when :children
            result["children"] = normalize_children(raw["children"], path: "#{path}.children", depth: depth + 1,
                                                                       allowed_kinds: NON_ROW_CONTAINER_KINDS)
          when :items
            result["items"] = normalize_items(raw["items"], component: component, level: descriptor[:nests],
                                                              path: "#{path}.items", depth: depth + 1)
          else
            if raw["children"] || raw["items"]
              add_warning("#{path}: '#{method_name}' takes no block, so children/items are ignored")
            end
          end

          result
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        def normalize_builder_item_args(descriptor, raw_args, method_name:, path:)
          required_keys = descriptor[:arg] ? [descriptor[:arg].to_s] : []

          normalize_required_args(stringify_keys(raw_args), required_keys, path: path) do |missing|
            add_error("#{path}: builder item '#{method_name}' is missing required arg(s): #{missing.join(', ')}")
          end
        end

        # --- Generic value sanitizing --------------------------------------------

        # Recursively strips Contract::FORBIDDEN_OPTIONS keys and
        # Contract::DANGEROUS_VALUE strings out of an arbitrary option/arg
        # value "at any depth" (rule 5), caps String length, and rejects
        # any type that isn't JSON-shaped (nil/Boolean/Integer/Float/
        # String/Hash/Array). #depth is #sanitize's own recursion guard
        # (SANITIZE_MAX_DEPTH), unrelated to tree node depth.
        def sanitize_generic_value(value, path:, depth: 0)
          return nil if depth > SANITIZE_MAX_DEPTH

          case value
          when String
            if Contract::DANGEROUS_VALUE.match?(value)
              add_error("#{path}: rejected (matches a dangerous value pattern)")
              return nil
            end
            value.length > Contract::LIMITS[:string] ? truncate_with_warning(value, path) : value
          when true, false, Integer, Float, NilClass
            value
          when Hash
            stringify_keys(value).each_with_object({}) do |(key, val), out|
              if Contract::FORBIDDEN_OPTIONS.include?(key)
                add_error("#{path}.#{key}: forbidden option stripped -- 'auth' is never allowed in a design tree")
                next
              end
              sanitized = sanitize_generic_value(val, path: "#{path}.#{key}", depth: depth + 1)
              out[key] = sanitized unless sanitized.nil?
            end
          when Array
            value.first(Contract::LIMITS[:children_per_node])
                 .filter_map { |v| sanitize_generic_value(v, path: "#{path}[]", depth: depth + 1) }
          else
            add_warning("#{path}: unsupported value type #{value.class}, dropped")
            nil
          end
        end

        def truncate_with_warning(value, path)
          add_warning("#{path}: truncated to #{Contract::LIMITS[:string]} characters")
          value[0, Contract::LIMITS[:string]]
        end

        # --- Small shared helpers -------------------------------------------------

        def stringify_keys(value)
          value.is_a?(Hash) ? value.each_with_object({}) { |(k, v), h| h[k.to_s] = v } : {}
        end

        def as_capped_hash(value, path:, limit:)
          if !value.nil? && !value.is_a?(Hash)
            add_warning("#{path}: expected an object, got #{value.class}, ignoring")
            return {}
          end

          hash = stringify_keys(value)
          return hash unless hash.size > limit

          add_warning("#{path}: #{hash.size} keys exceeds the #{limit} limit; extra keys dropped")
          hash.first(limit).to_h
        end

        def as_capped_array(value, path:, limit:)
          if !value.nil? && !value.is_a?(Array)
            add_warning("#{path}: expected an array, got #{value.class}, ignoring")
            return []
          end

          arr = value || []
          return arr unless arr.length > limit

          add_warning("#{path}: #{arr.length} items exceeds the #{limit} limit; extras dropped")
          arr.first(limit)
        end

        def add_error(message)
          @errors << message
        end

        def add_warning(message)
          @errors << "warning: #{message}"
        end
      end
    end
  end
end
