# frozen_string_literal: true

require "tabler_ui/docs/editor/contract"
require "tabler_ui/docs/editor/builder_map"

module TablerUi
  module Docs
    module Editor
      # Turns one design tree (Contract's node shapes -- see contract.rb) into
      # real HTML by calling the real component dispatcher with structured
      # data, the same way a host app's ERB does via `tabler_ui.<name>(...)`.
      #
      # ## Never `render inline:`, never build+eval an ERB string
      #
      # This editor ships inside a mountable engine, so it runs in every host
      # app that installs it. An endpoint that turned attacker-controlled JSON
      # into an ERB source string and evaluated it would be remote code
      # execution in every one of those apps. docs/lib/tabler_ui/docs/parsed_component.rb
      # and docs/app/views/tabler_ui/docs/components/show.html.erb both carry
      # the same warning for the same reason. This class only ever calls
      # `view.tabler_ui.public_send(name, **opts, &block)` with a Hash built
      # from the tree -- never `render inline:`, never `eval`, never string
      # interpolation into a template source. A `partial` node's `path` is
      # NEVER passed to Rails' `render` either -- see #render_partial_node.
      #
      # ## The tree is assumed already normalized
      #
      # A separate Tree module (another agent's file) validates a design tree
      # before it ever reaches here: node shapes, the `args`/`options` key
      # split, the attribute allowlist, the component-name allowlist, the
      # `auth` strip. This class does NOT re-validate any of that -- it walks
      # the tree and dispatches. The one exception is `Contract::LIMITS[:depth]`,
      # re-checked here as defense in depth (see #render_node): a validator
      # bug must not become a `SystemStackError`, which is NOT a
      # `StandardError` and would escape the per-node `rescue` below,
      # crashing the whole worker rather than producing one error marker.
      # This same depth counter is what bounds a `partial` -> `partial` cycle
      # across files (see #render_partial_node) even though that isn't
      # "nesting" in the single-tree sense -- every hop through either one
      # increments the same counter.
      #
      # ## Error isolation granularity
      #
      # Every node's render is wrapped in `rescue StandardError` (#render_node)
      # so one bad node renders an inline `.alert-danger` marker instead of
      # taking the whole preview down -- component options failing
      # `TablerUi::Color.validate!`/friends, or a builder's `validate!` hook
      # (steps' `current:` bounds check, carousel's exactly-one-active,
      # accordion's open-count) all surface this way. That isolation is at
      # the *design-tree node* level (a `component`/`row`/`column`/... entry),
      # not inside a single builder component's own item list: `tabs`,
      # `navbar`, `accordion` and friends collect every item first and render
      # them all in one template pass with no per-item render boundary of
      # their own, so a bad item invalidates that one component into a single
      # marker rather than being isolated further -- its *sibling design-tree
      # nodes* elsewhere are unaffected. See #emit_item.
      #
      # ## Stamping
      #
      # Every node that renders its own DOM element carries
      # `data-editor-node-id="<id>"` so the editor's click-to-select can map
      # DOM back to tree (`fragment` has no element of its own, so it isn't
      # stamped). For a `component` node this is deep-merged into the
      # caller's own `root`-part `html:` hash *deliberately* -- see
      # #stamp_editor_id -- rather than routed through
      # `TablerUi::HtmlOptions.merge_html`, whose documented contract lets the
      # caller's own `data:` win on key collision, which would let a crafted
      # `data: { editor_node_id: ... }` in the design clobber the real one.
      # `heading`/`text` additionally carry `data-editor-field="content"` for
      # in-canvas text editing. `contenteditable` is never emitted here -- the
      # editor's own JS applies/removes it at runtime.
      class Renderer
        MAX_DEPTH = Contract::LIMITS.fetch(:depth)

        # @param view_context [ActionView::Base] a real view context with
        #   TablerUi::Helper mixed in, so `.tabler_ui` resolves
        # @param resolve [#call, nil] takes a partial path String, returns
        #   that file's design tree (a Hash) or nil. Never wired to Rails'
        #   own `render` -- see the class docs' RCE section.
        def initialize(view_context, resolve: nil)
          @view = view_context
          @resolve = resolve
        end

        # @param node [Hash] a Contract-shaped design tree node
        # @return [ActiveSupport::SafeBuffer]
        def render(node)
          render_node(node, 1)
        end

        private

        # --- Dispatch by kind -----------------------------------------------

        # @param depth [Integer] 1 for the tree's root node, incremented by
        #   every container/partial/builder-item/slot recursion below.
        def render_node(node, depth)
          return depth_marker(node) if depth > MAX_DEPTH

          case node["kind"]
          when "fragment"  then render_fragment_node(node, depth)
          when "row"       then render_row_node(node, depth)
          when "column"    then render_column_node(node, depth)
          when "heading"   then render_heading_node(node)
          when "text"      then render_text_node(node)
          when "component" then render_component_node(node, depth)
          when "partial"   then render_partial_node(node, depth)
          else
            error_marker(node, node["kind"].to_s, "unknown node kind")
          end
        rescue StandardError => e
          error_marker(node, (node["name"] || node["kind"]).to_s, e.message)
        end

        # Root only, per Contract -- no element of its own, so no stamp.
        def render_fragment_node(node, depth)
          render_children(node["children"], depth + 1)
        end

        def render_row_node(node, depth)
          attrs = merge_editor_attrs({ class: "row" }, node["attrs"], node["id"])
          @view.tag.div(**attrs) { render_children(node["children"], depth + 1) }
        end

        def render_column_node(node, depth)
          attrs = merge_editor_attrs({ class: span_classes(node["span"]) }, node["attrs"], node["id"])
          @view.tag.div(**attrs) { render_children(node["children"], depth + 1) }
        end

        # `content` is plain text, always -- see Contract's "deliberately
        # absent" section (no raw-HTML node kind exists). `content_tag`'s
        # 2nd positional argument is escaped by default; that escaping is
        # the whole point of this method existing rather than `tag.h#{n}`
        # with a block (a block's return value is NOT auto-escaped).
        def render_heading_node(node)
          tag_name = "h#{node['level'] || 1}"
          @view.content_tag(tag_name, node["content"].to_s, editor_field_attrs(node["id"]))
        end

        def render_text_node(node)
          tag_name = node["tag"] || "p"
          @view.content_tag(tag_name, node["content"].to_s, editor_field_attrs(node["id"]))
        end

        def editor_field_attrs(id)
          { data: { editor_node_id: id, editor_field: "content" } }
        end

        # Builder-style vs. slot-style is decided by `Component.builder_style?`
        # (declared via `builder_style!`, lib/tabler_ui/base.rb) -- not by
        # guessing from which of `items`/`slots` the node happens to carry.
        # A component that is neither gets no block at all, matching how a
        # caller with nothing to add would write the ERB by hand.
        def render_component_node(node, depth)
          name = node.fetch("name")
          klass = component_class_for(name)
          opts = component_opts(node)

          if klass.respond_to?(:builder_style?) && klass.builder_style?
            @view.tabler_ui.public_send(name, **opts) do |builder|
              emit_items(builder, node["items"], name, :root, depth + 1)
            end
          elsif node["slots"].present?
            @view.tabler_ui.public_send(name, **opts) do |slots|
              emit_slots(slots, node["slots"], depth + 1)
            end
          else
            @view.tabler_ui.public_send(name, **opts)
          end
        end

        # `path` is resolved purely against whatever `resolve:` returns and
        # THAT result -- a design tree -- is what gets recursed into. `path`
        # itself never reaches Rails' `render`: doing so would let a crafted
        # design reach into the *host app's* own view paths (see class docs).
        # `resolve:` nil, or returning nil (unknown/unwired path), is not an
        # error -- it's the expected shape before multi-file resolution is
        # wired up, so it renders an inline marker instead of raising.
        def render_partial_node(node, depth)
          path = node["path"]
          tree = @resolve && @resolve.call(path)
          return render_node(tree, depth + 1) if tree

          error_marker(node, "partial", "unresolved partial: #{path.inspect}")
        end

        def render_children(nodes, depth)
          @view.safe_join(Array(nodes).map { |child| render_node(child, depth) }, "")
        end

        # --- Builder-style items ---------------------------------------------

        # Walks one level of BuilderMap (see that file's "Shape" section).
        # `component_name`/`level` select the method-name => descriptor Hash;
        # recursing into a `block: :items` method's own `nests:` level is how
        # navbar's `left`/`right` -> `add`/`dropdown` -> `item` all fall out
        # of the exact same code, with no `if component_name == "navbar"`
        # anywhere here.
        def emit_items(builder, items, component_name, level, depth)
          return if depth > MAX_DEPTH

          Array(items).each { |item| emit_item(builder, item, component_name, level, depth) }
        end

        # Deliberately NOT individually rescued -- see the class docs' "Error
        # isolation granularity" section. A builder method only queues data
        # (`@items << Item.new(...)`); the HTML for it doesn't exist until
        # the enclosing component's own template renders every item in one
        # pass back in TablerUi::Ui#render_block, well after this method
        # returns. There is no DOM slot here to swap in a marker for just
        # this one item, so an exception propagates out to #render_node's
        # rescue for the enclosing `component` node, which is the real
        # error-isolation boundary for builder items.
        #
        # Calling convention is derived by reflection (`builder.method(...)`),
        # not hardcoded per method: every builder method here takes its
        # (optional) required positional plus a trailing `options = {}` Hash
        # EXCEPT `pagination#gap`, which takes none at all (BuilderMap's own
        # comment flags it as the one exception) -- `meth.arity.zero?` is
        # what tells `gap` apart from e.g. `dropdown#divider(options = {})`
        # without special-casing either by name.
        def emit_item(builder, item, component_name, level, depth)
          method_name = item["method"]
          descriptor = BuilderMap.methods_for(component_name, level)[method_name]
          unless descriptor
            raise ArgumentError, "unknown builder method #{method_name.inspect} for #{component_name}##{level}"
          end

          meth = builder.method(method_name)
          call_args = descriptor[:arg] ? [item.dig("args", descriptor[:arg].to_s)] : []
          call_args << builder_item_opts(item) unless meth.arity.zero?

          case descriptor[:block]
          when :items
            nested_level = descriptor.fetch(:nests)
            builder.public_send(method_name, *call_args) do |nested|
              emit_items(nested, item["items"], component_name, nested_level, depth + 1)
            end
          when :children
            builder.public_send(method_name, *call_args) { render_children(item["children"], depth + 1) }
          else
            builder.public_send(method_name, *call_args)
          end
        end

        # --- Slot-style components -------------------------------------------

        def emit_slots(slots, slot_hash, depth)
          slot_hash.each do |slot_name, children|
            slots.public_send(slot_name) { render_children(children, depth) }
          end
        end

        # --- Option / HTML-hook building --------------------------------------

        def component_class_for(name)
          "TablerUi::#{name.to_s.camelize}::Component".safe_constantize
        end

        # `args` (required positionals, keyed by parameter name) and
        # `options` never share a key -- Contract guarantees that, the
        # validator enforces it -- so merging them into one kwargs Hash and
        # handing it to `tabler_ui.<name>(**opts)` is safe: TablerUi::Ui's own
        # `build_modern_component` already knows how to pull the required
        # positional(s) back out by parameter name (lib/tabler_ui/ui.rb), so
        # this class doesn't need its own list of which 8 components have a
        # mandatory positional -- it falls out of the dispatcher for free.
        def component_opts(node)
          opts = symbolize(node["options"])
          opts.merge!(symbolize(node["args"]))
          opts.merge(build_html_opts(node["html"], node["id"]))
        end

        # A builder item's own `html:` hook -- e.g. accordion's `item` takes
        # `html:`/`header_html:`/`body_html:` on itself, same part-keying as
        # a component. `args` is NOT merged in here (unlike #component_opts):
        # a builder item's required value is passed positionally by
        # #emit_item, never inside its options Hash.
        def builder_item_opts(item)
          symbolize(item["options"]).merge(build_html_opts(item["html"], item["id"]))
        end

        # `html_by_part` is keyed by PART ("root", "header", ...), the
        # component's own vocabulary (Contract's own note on this). "root"
        # maps to the `html:` kwarg, any other part to `"#{part}_html"`.
        # `:html` is always present in the result, even when the node
        # supplied no `html` at all, since the id marker must always land.
        def build_html_opts(html_by_part, id)
          result = {}
          (html_by_part || {}).each do |part, attrs|
            key = part == "root" ? :html : :"#{part}_html"
            result[key] = symbolize(attrs)
          end
          result[:html] = stamp_editor_id(result[:html], id)
          result
        end

        # Deliberate, not routed through TablerUi::HtmlOptions.merge_html --
        # see the class docs' "Stamping" section for why. The caller's own
        # `data:` keys are kept (spread first); `editor_node_id` is set last
        # so it always wins, regardless of what the design supplied.
        def stamp_editor_id(html_hash, id)
          html_hash = symbolize(html_hash)
          html_hash.merge(data: symbolize(html_hash[:data]).merge(editor_node_id: id))
        end

        # Same deliberate-last-write approach as #stamp_editor_id, for the
        # plain `row`/`column` wrapper `<div>`s -- merge_html's "overrides
        # wins on collision" semantics are fine for `class`/other attrs here
        # (there's no security-sensitive key to protect the way there is on
        # a component's `html:`), but the id itself is still set explicitly
        # afterwards rather than trusted to fall out of that merge correctly.
        def merge_editor_attrs(base, attrs, id)
          merged = TablerUi::HtmlOptions.merge_html(base, symbolize(attrs))
          merged.merge(data: symbolize(merged[:data]).merge(editor_node_id: id))
        end

        def symbolize(hash)
          (hash || {}).each_with_object({}) { |(k, v), acc| acc[k.to_s.to_sym] = deep_symbolize(v) }
        end

        # Symbolizing only an option's own top-level key is not enough. Tree
        # normalizes every Hash key at every depth to a String, but components
        # read structured option values with Symbol keys -- table's own
        # template does `col[:label]` on each entry of `columns:` -- so a
        # String-keyed Hash reaches the component and every lookup returns
        # nil, rendering empty cells. ErbGenerator meanwhile emits `label:`,
        # a real Symbol at runtime, so the EXPORTED code worked while the
        # preview silently did not: the preview lied about the export, which
        # is the worst failure this feature can have. Caught by the
        # renderer/generator equivalence corpus (consistency_spec.rb).
        #
        # RUBY_LABEL mirrors ErbGenerator's constant of the same name on
        # purpose: the generator emits a Symbol key only where the key is a
        # valid Ruby label and a String key otherwise ("data-bs-toggle"),
        # so matching that rule exactly is what keeps the two in agreement.
        # Only option/arg values pass through here -- `html:` hooks are built
        # separately by #build_html_opts and keep their own key handling.
        RUBY_LABEL = /\A[A-Za-z_][A-Za-z0-9_]*[?!]?\z/

        def deep_symbolize(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), acc|
              key = k.to_s
              acc[key.match?(RUBY_LABEL) ? key.to_sym : key] = deep_symbolize(v)
            end
          when Array then value.map { |element| deep_symbolize(element) }
          else value
          end
        end

        # `span` is `{"base" => 12, "md" => 6}` -> "col-12 col-md-6".
        # Iterates Contract::SPAN_KEYS (not the Hash's own key order) so the
        # class list is deterministic regardless of how the tree serialized
        # the span Hash.
        def span_classes(span)
          span ||= {}
          keys = Contract::SPAN_KEYS.select { |k| span.key?(k) }
          return "col" if keys.empty?

          keys.map { |k| k == "base" ? "col-#{span[k]}" : "col-#{k}-#{span[k]}" }.join(" ")
        end

        # --- Error markers -----------------------------------------------------

        # `message` may echo back part of a raised error (e.g. an invalid
        # option value the caller supplied), so it goes through content_tag's
        # normal escaping like any other user-influenced text -- never `raw`.
        def error_marker(node, label, message)
          @view.content_tag(:div, "#{label}: #{message}", class: "alert alert-danger",
                                                            data: { editor_node_id: node["id"] })
        end

        def depth_marker(node)
          error_marker(node, node["kind"].to_s, "exceeds max depth (#{MAX_DEPTH})")
        end
      end
    end
  end
end
