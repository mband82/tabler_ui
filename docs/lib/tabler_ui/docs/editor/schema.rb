# frozen_string_literal: true

require "tabler_ui/docs/navigation"
require "tabler_ui/docs/doc_parser"
require "tabler_ui/docs/engine"
require "tabler_ui/docs/editor/contract"
require "tabler_ui/docs/editor/slot_map"
require "tabler_ui/docs/editor/builder_map"
require "tabler_ui/docs/editor/enum_map"

module TablerUi
  module Docs
    module Editor
      # The design editor's schema endpoint payload: everything the
      # in-browser editor's component palette and property panels need,
      # assembled from the three registries (SlotMap, BuilderMap, EnumMap),
      # Contract's own limits, Navigation's category grouping, and
      # DocParser's parsed `@option` rows -- no separate content is authored
      # for the editor, so this can never drift from what the docs pages
      # themselves already describe (same reasoning as SearchIndex).
      #
      # ## Shape
      #
      #   { "version" => 1,
      #     "limits"  => { "bytes" => 262144, ... },        # Contract::LIMITS, string-keyed
      #     "layout"  => [ { "kind" => "row" }, ... ],       # Contract::KINDS minus the three
      #                                                       # kinds that aren't a generic palette
      #                                                       # drag item -- "fragment" is root-only,
      #                                                       # "component"/"builder_item" are covered
      #                                                       # by "components" below instead
      #     "categories" => [ { "label" => "Layout", "components" => [...] }, ... ],
      #     "components" => { "card" => { ... }, ... } }
      #
      # Each entry of "components" (see #component_payload):
      #
      #   { "title"       => "Card",
      #     "description" => "...",             # ParsedComponent#description, squished
      #     "docPath"     => "/ui/components/card",  # via Engine.routes.url_helpers -- never hardcoded
      #     "args"        => [ { "name" => "id", "control" => "text", "required" => true } ],
      #     "options"     => [ { "name" => ..., "control" => ..., "type" => ..., "default" => ...,
      #                          "description" => ..., "values" => [...], "symbol" => bool,
      #                          "fields" => [...] } ],
      #     "htmlParts"   => ["root", "header", "body", "footer"],
      #     "slots"       => ["body", "footer", "header"],
      #     "builder"     => nil,   # or { "root" => { "item" => { "arg" => {...}|nil, "block" => ...,
      #                             #      "nests" => ..., "options" => [...], "htmlParts" => [...],
      #                             #      "unsupported" => [...] } } }
      #     "unsupported" => [ { "name" => ..., "type" => ..., "reason" => "callable" } ] }
      #
      # `args` metadata is recovered by reflection
      # (`instance_method(:initialize).parameters`), not from doc comments --
      # DocParser only structures `@option options [Type] :name` rows, never
      # the `@param id [String] ...` line documenting a mandatory positional,
      # so there is nothing in ParsedComponent to read a type or description
      # from for these. Only 8 components have one at all (accordion,
      # carousel, modal, offcanvas, settings_page, tabs -- all `id` -- plus
      # icon's `icon` and illustration's `name`); every entry gets
      # `control: "text"` since the positional is always a plain identifier
      # string in every one of the 8. "values"/"symbol" are present only on
      # a `"control" => "select"` option, "fields" only on a `"control" =>
      # "columns"` one (today, only table's :columns -- see
      # DECLARATIVE_CONTROLS/COLUMN_FIELDS below) -- every other control
      # omits all three rather than carrying them as null, so a client can
      # branch on key presence alone.
      #
      # `auth` (Contract::FORBIDDEN_OPTIONS) is dropped at every level --
      # top-level options, builder sub-method options -- before any other
      # rule runs. See Contract's own header for why this is a security
      # control (auth: reaches host authorization code) and not merely a
      # product choice; schema_spec.rb sweeps the whole serialized payload
      # for the literal string "auth" to guard it.
      #
      # ## Control-type derivation (#control_for)
      #
      # An option's `type` string (e.g. "Boolean, String") is split on
      # `/\s*,\s*/` into a type set, then classified in this fixed order --
      # first match wins:
      #
      #   0. (handled by the DECLARATIVE_CONTROLS lookup, also before
      #      #control_for -- see that constant's own doc) a (component,
      #      option) pair with an entry there gets that entry's control
      #      outright, type string never even inspected. Exists for exactly
      #      table's :columns ("columns") and :data ("rows") today -- both
      #      would otherwise fall through to the generic "json" control via
      #      rule 7 below, same as datagrid's :items/rating's :choices,
      #      which share :columns' own "Array<Hash>" type but stay on rule
      #      7 since they aren't in this table.
      #   1. (handled by #html_part_for, before #control_for is ever
      #      called) name == "html" or ends "_html" -> not an option at all,
      #      contributes to htmlParts instead ("header_html" -> "header",
      #      bare "html" -> "root").
      #   2. (handled by the EnumMap lookup, also before #control_for)
      #      EnumMap has an entry for (component, option) -> "select", with
      #      "values"/"symbol" from EnumMap.values_for/.symbol?. Applied by
      #      option NAME alone, not by level -- confirmed correct even for a
      #      builder sub-method's own option (e.g. navbar's nested
      #      NavigationGroup#dropdown `:align`, GLOBAL's plain Align
      #      vocabulary applies there exactly as it does anywhere else
      #      `:align` appears).
      #   3. set includes "Boolean" -> "checkbox". Checked before
      #      Integer/Numeric and before the String/Symbol-subset rule, so a
      #      mixed set like "Integer, Boolean" (carousel's :interval,
      #      ms-or-false) or "Boolean, Symbol, String" (offcanvas's
      #      :backdrop, true/false/:static) resolves to a boolean toggle,
      #      not a number/text field -- the boolean is always the primary
      #      on/off switch on every option that mixes it with something
      #      else in this codebase.
      #   4. set includes "Integer" or "Numeric" -> "number"
      #   5. set (after dropping "nil" and folding
      #      "ActiveSupport::SafeBuffer" into "String" -- see below) is a
      #      non-empty subset of {"String", "Symbol"} -> "text"
      #   6. set intersects {"Object", "#call", "Proc"} -> excluded, goes to
      #      "unsupported" with a reason ("callable" for #call/Proc,
      #      "opaque (Object)" otherwise)
      #   7. set, sorted, is one of STRUCTURED_TYPE_SETS -> "json" (an
      #      advanced escape-hatch control for a structured value with no
      #      scalar UI equivalent -- table's :columns/:data, datagrid's
      #      :items, rating's :choices, placeholder's :lines, pagination/
      #      table's :frame)
      #   8. anything else -> raises UnknownTypeError
      #
      # Two normalizations happen before rule 3 even runs, both deliberate
      # extensions of the plain "split on comma" reading, documented here
      # because they are a judgment call, not something dictated anywhere
      # else:
      #
      #   * A literal "nil" entry (e.g. alert's "String, nil" :title) is
      #     dropped -- it marks the option as optional/nullable, which every
      #     option already is by virtue of living in the trailing options
      #     Hash; it is not itself a control-relevant type. Without dropping
      #     it, "String, nil" would fail the String/Symbol-subset test on a
      #     technicality and wrongly fall through toward "unsupported".
      #   * "ActiveSupport::SafeBuffer" (badge's :content) is folded into
      #     "String" -- it IS a String subclass in Ruby, so from the editor's
      #     perspective both are edited as plain text; Contract's own "no
      #     raw/html_safe content" rule means a value sent back from the
      #     editor is always a plain String anyway, never actually a
      #     SafeBuffer.
      #
      # Rule 7's STRUCTURED_TYPE_SETS is an explicit allowlist, not an
      # open-ended "anything left over" catch-all, on purpose: an
      # open-ended fallback would silently swallow a genuinely new type
      # string a future component introduces, exactly the failure mode the
      # module doc's "anti-rot" spec exists to catch. A real 24-value type
      # vocabulary exists across DocParser.all today (see schema_spec.rb) --
      # every one of those 24 strings resolves through rules 1-7 above
      # without reaching rule 8.
      module Schema
        # Raised by #control_for when a type string matches none of the
        # documented rules -- see the module doc's "Control-type derivation"
        # section. Deliberately loud: a silent fallback here would mean a
        # newly-added component's option quietly renders as the wrong
        # control (or none at all) instead of failing the build/spec run
        # that introduced it.
        class UnknownTypeError < StandardError; end

        # Contract::KINDS minus the three kinds a generic "drag onto the
        # canvas" palette never offers directly: "fragment" is root-only
        # (never a child a user drops), and "component"/"builder_item" are
        # covered by the "components" section of the payload instead of
        # the plain "layout" section. Derived from Contract::KINDS itself,
        # not a separate literal list, so it cannot drift if Contract ever
        # gains or removes a kind.
        LAYOUT_KINDS = (Contract::KINDS - %w[fragment component builder_item]).freeze

        # Type sets (already comma-split, "nil" dropped, SafeBuffer folded
        # into String, and sorted) that resolve to the "json" advanced
        # escape-hatch control -- see the module doc's rule 7. Explicit and
        # exhaustive rather than a generic "contains Hash" rule, so a
        # genuinely new structured type raises instead of silently landing
        # here. Every entry was confirmed against a real option today (see
        # each comment).
        #
        # table's own :columns ("Array<Hash>") and :data ("Enumerable") are
        # intercepted by DECLARATIVE_CONTROLS below, keyed by (component,
        # option) rather than by type, before #control_for/this list ever
        # runs for them -- see that constant's doc. Both type strings stay
        # listed here regardless: #control_for itself is still exercised
        # directly, type-string-only, by every other Array<Hash>/Enumerable
        # option (datagrid's :items, rating's :choices) and by
        # schema_spec.rb's "type vocabulary anti-rot" sweep over every
        # distinct type string DocParser finds, table's included.
        STRUCTURED_TYPE_SETS = [
          %w[Hash],           # bare Hash -- table's :sort/:filter, most *_html hooks (handled earlier, but
                               # the type itself is still just "Hash")
          %w[Hash String],    # "String, Hash" -- pagination's/table's :frame
          %w[Array<Hash>],    # datagrid's :items, rating's :choices (table's :columns is overridden -- see above)
          %w[Array<Integer>], # placeholder's :lines
          %w[Enumerable]      # table's :data would land here too, but is overridden -- see above
        ].freeze

        # (component, option name) => dedicated editor control, bypassing
        # #control_for (and its type-string-only view of the world)
        # entirely for exactly these pairs. table's :columns/:data need
        # more than the generic "json" escape hatch: :columns holds a
        # declarative per-column shape (Renderer#synthesize_table_columns /
        # ErbGenerator#format_columns_array both key off it) that a real
        # property-panel control can build a form from, and :data is the
        # matching row editor. Scoped by (component, option) -- not by type
        # string -- so this can never accidentally swallow datagrid's
        # :items or rating's :choices, which share :columns' own
        # "Array<Hash>" type string but have no `key:`/callable concept at
        # all.
        DECLARATIVE_CONTROLS = {
          "table" => { "columns" => "columns", "data" => "rows" }
        }.freeze

        # Declarative sub-fields a "columns" control's UI can build one
        # column's edit form from -- see Renderer#synthesize_column /
        # ErbGenerator#format_column_entry for the two places that actually
        # consume them. Deliberately narrower than every key
        # Table::Component's real :columns hash accepts (see that
        # component's own @option :columns doc):
        #
        #   * `key`   -- NEW, editor-only. Not a real Table::Component
        #     option at all; it's what both Renderer and ErbGenerator
        #     synthesize `value:` from. The one mandatory field.
        #   * `label`, `class` -- real column keys, simple enough (plain
        #     String) to round-trip through a text control as-is.
        #
        # Deliberately left out:
        #
        #   * `value` -- the whole reason this control exists: a raw
        #     callable can never come from JSON, and the tree must never
        #     let a user-supplied string be treated as one (see both
        #     modules' own doc comments on this) -- so there is no field
        #     for it at all, declarative or otherwise; `key` is the only
        #     way to make a cell render something.
        #   * `sort` -- a column's `sort:` is only meaningful alongside the
        #     table-level `sort_url:`, and `sort_url:` is itself a callable
        #     (`#call`, reported in `unsupported`, same as `value` would
        #     be) that a design tree can never supply. Offering a per-column
        #     sort field with no way to ever give it a working `sort_url:`
        #     would just be a control that always breaks the table
        #     (Table::Component#guard_sort_url! raises ArgumentError,
        #     caught only as a whole-node error marker -- see Renderer's
        #     error-isolation doc) the moment it's used. Left out until the
        #     editor has some other way to wire up sort_url:.
        #   * `sort_url` -- table-level, not per-column, and itself a
        #     callable -- already correctly reported as `unsupported`
        #     (reason: "callable") via the ordinary #control_for path.
        COLUMN_FIELDS = [
          { "name" => "key", "control" => "text", "required" => true },
          { "name" => "label", "control" => "text", "required" => false },
          { "name" => "class", "control" => "text", "required" => false }
        ].freeze

        # `/(default: ...)/ ` inside an option's description -- a lossy,
        # best-effort recovery of the default mentioned in prose. Used only
        # as a placeholder hint for the property panel; never fed back into
        # a design automatically (see the module doc on FORBIDDEN_OPTIONS
        # for the same "never auto-write" spirit applied to `auth`).
        DEFAULT_IN_DESCRIPTION = /\(default:\s*([^)]+)\)/.freeze

        module_function

        # @return [Hash] the full payload, memoized -- see #reset!.
        def as_json
          @as_json ||= build
        end

        # Drops the memoized payload. Not needed for normal operation --
        # exists for specs that want a clean slate (see schema_spec.rb's
        # `around` block, and the module doc's note on this suite's
        # order-dependent global state).
        def reset!
          @as_json = nil
        end

        # Rebuilds the payload from scratch, unmemoized. #as_json is the
        # normal entry point; this is exposed separately so a spec can
        # compare two independent builds without reaching into the ivar
        # (mirrors SearchIndex.build).
        #
        # @return [Hash]
        def build
          {
            "version" => Contract::VERSION,
            "limits" => Contract::LIMITS.transform_keys(&:to_s),
            "layout" => LAYOUT_KINDS.map { |kind| { "kind" => kind } },
            "categories" => Navigation.category_names.map { |label| category_payload(label) },
            "components" => Navigation.components.each_with_object({}) { |name, out| out[name] = component_payload(name) }
          }
        end

        # @api private
        def category_payload(label)
          { "label" => label, "components" => Navigation.components_in(label) }
        end

        # @api private
        # @return [Hash] one "components" entry -- see the module doc's
        #   "Shape" section.
        def component_payload(name)
          parsed = DocParser.find(name) || ParsedComponent.new(name)
          options, unsupported, html_parts = classify_options(name, parsed.options)

          {
            "title" => Navigation.title_for(name),
            "description" => squish_or_nil(parsed.description),
            "docPath" => Engine.routes.url_helpers.component_path(name),
            "args" => args_for(name),
            "options" => options,
            "htmlParts" => html_parts,
            "slots" => SlotMap.slots_for(name),
            "builder" => builder_for(name),
            "unsupported" => unsupported
          }
        end

        # @api private
        # @return [Array<Hash>] required-positional metadata, recovered by
        #   reflection (see the module doc for why DocParser can't supply
        #   this) -- [] for any of the 27 components with no mandatory
        #   positional argument.
        def args_for(name)
          component_class(name).instance_method(:initialize).parameters
                                .select { |type, _name| type == :req }
                                .map { |_type, pname| { "name" => pname.to_s, "control" => "text", "required" => true } }
        end

        # @api private
        # @return [Class] e.g. TablerUi::Card::Component for "card"
        def component_class(name)
          "TablerUi::#{name.camelize}::Component".constantize
        end

        # @api private
        # @return [Hash, nil] the builder sections for a builder-style
        #   component (see BuilderMap), keyed by level name -- "root", and
        #   for navbar also "group"/"dropdown" -- each holding method name
        #   => method payload. nil for a non-builder-style component.
        def builder_for(name)
          levels = BuilderMap.levels_for(name)
          return nil if levels.empty?

          builder_options_by_klass = DocParser.builder_options(name)

          levels.each_with_object({}) do |(level, methods), levels_out|
            levels_out[level.to_s] = methods.each_with_object({}) do |(method_name, descriptor), methods_out|
              methods_out[method_name] = builder_method_payload(name, method_name, descriptor, builder_options_by_klass)
            end
          end
        end

        # @api private
        # @return [Hash] one builder method's payload -- see the module
        #   doc's "Shape" section for the "builder" key.
        def builder_method_payload(component, method_name, descriptor, builder_options_by_klass)
          # builder_options is keyed by the enclosing class's BARE name
          # ("NavigationGroup"), while a descriptor's klass: may be a
          # compound path relative to the component ("Component::
          # NavigationGroup") -- see BuilderMap's own doc and the module
          # doc above. .split("::").last bridges the two.
          bare_klass = descriptor[:klass].split("::").last
          raw_options = builder_options_by_klass.dig(bare_klass, method_name) || []
          options, unsupported, html_parts = classify_options(component, raw_options)

          payload = {
            "arg" => arg_payload(descriptor[:arg]),
            "block" => descriptor[:block]&.to_s,
            "options" => options,
            "htmlParts" => html_parts,
            "unsupported" => unsupported
          }
          payload["nests"] = descriptor[:nests].to_s if descriptor[:nests]
          payload
        end

        # @api private
        def arg_payload(arg_name)
          return nil unless arg_name

          { "name" => arg_name.to_s, "control" => "text", "required" => true }
        end

        # @api private
        # Shared by both top-level options (DocParser.find(component).options)
        # and a single builder method's options (one value of
        # DocParser.builder_options(component)) -- same rules apply at
        # either level (see the module doc's rule 2 note on EnumMap being
        # keyed by option name alone, not by level).
        #
        # @param component [String] component name, for EnumMap lookups
        # @param raw_options [Array<ParsedComponent::Option>]
        # @return [(Array<Hash>, Array<Hash>, Array<String>)] options,
        #   unsupported, htmlParts -- three separate lists so the caller can
        #   drop each into its own payload key without re-filtering.
        def classify_options(component, raw_options)
          options = []
          unsupported = []
          html_parts = []

          raw_options.each do |opt|
            next if Contract::FORBIDDEN_OPTIONS.include?(opt.name)

            part = html_part_for(opt.name)
            if part
              html_parts << part
              next
            end

            declarative_control = DECLARATIVE_CONTROLS.dig(component, opt.name)
            if declarative_control
              options << option_payload(opt, declarative_control)
              next
            end

            enum_entry = EnumMap.entry_for(component, opt.name)
            if enum_entry
              options << option_payload(opt, "select", component: component)
              next
            end

            control = control_for(opt.type)
            if control == :unsupported
              unsupported << { "name" => opt.name, "type" => opt.type, "reason" => unsupported_reason(opt.type) }
            else
              options << option_payload(opt, control.to_s)
            end
          end

          [options, unsupported, html_parts.uniq]
        end

        # @api private
        # @return [String, nil] "root" for the bare :html hook, the part
        #   name for a "<part>_html" hook, or nil for an ordinary option.
        def html_part_for(name)
          return "root" if name == "html"
          return name.delete_suffix("_html") if name.end_with?("_html")

          nil
        end

        # @api private
        def option_payload(opt, control, component: nil)
          payload = {
            "name" => opt.name,
            "control" => control,
            "type" => opt.type,
            "default" => default_for(opt.description),
            "description" => squish_or_nil(opt.description)
          }

          if control == "select"
            payload["values"] = EnumMap.values_for(component, opt.name)
            payload["symbol"] = EnumMap.symbol?(component, opt.name)
          elsif control == "columns"
            payload["fields"] = COLUMN_FIELDS
          end

          payload
        end

        # @api private
        # @return [String, nil] a lossy, best-effort default recovered from
        #   "(default: ...)" in the option's description -- see
        #   DEFAULT_IN_DESCRIPTION's own doc.
        def default_for(description)
          match = DEFAULT_IN_DESCRIPTION.match(description.to_s)
          match && match[1].strip
        end

        # @api private
        # @return [String] "callable" when the type set includes a
        #   callable marker (#call, Proc), "opaque (Object)" otherwise --
        #   the only two ways rule 6 (see module doc) can be reached.
        def unsupported_reason(type_string)
          types = type_string.to_s.split(/\s*,\s*/)
          (types & ["#call", "Proc"]).any? ? "callable" : "opaque (Object)"
        end

        # @api private
        # @return [Symbol] :checkbox, :number, :text, :unsupported or :json
        # @raise [UnknownTypeError] for a type string matching none of the
        #   documented rules -- see the module doc's "Control-type
        #   derivation" section for the full, ordered rule list and why
        #   this is a raise rather than a silent fallback.
        def control_for(type_string)
          types = type_string.to_s.split(/\s*,\s*/).reject { |t| t == "nil" }
          types = types.map { |t| t == "ActiveSupport::SafeBuffer" ? "String" : t }.uniq

          return :checkbox if types.include?("Boolean")
          return :number if (types & %w[Integer Numeric]).any?
          return :text if types.any? && (types - %w[String Symbol]).empty?
          return :unsupported if (types & ["Object", "#call", "Proc"]).any?
          return :json if STRUCTURED_TYPE_SETS.include?(types.sort)

          raise UnknownTypeError, "no control mapping for type #{type_string.inspect} -- " \
                                   "add a rule to TablerUi::Docs::Editor::Schema.control_for"
        end

        # @api private
        # @return [String, nil] whitespace-squished text, or nil for a
        #   blank/absent description -- never an empty string.
        def squish_or_nil(text)
          text.to_s.squish.presence
        end
      end
    end
  end
end
