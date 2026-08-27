# frozen_string_literal: true

require "tabler_ui/docs/editor/contract"
require "tabler_ui/docs/editor/builder_map"
require "tabler_ui/docs/editor/sort_url"
require "tabler_ui/docs/editor/slot_map"
require "tabler_ui/docs/editor/slot_parts"
require "tabler_ui/docs/editor/builder_parts"

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
      #
      # A builder item whose method takes a `block: :children` (BuilderMap's
      # own vocabulary -- `accordion.item`, `tabs.tab`, ...) ALSO gets its
      # own content pane stamped -- `data-editor-builder-content="true"`
      # alongside a second `data-editor-node-id` naming that same item, on
      # whichever part BuilderParts.part_for resolves for that (component,
      # method) pair (#stamp_builder_content / #synthesize_datagrid_
      # content_marker). Unlike the plain id/field stamps just above, this
      # IS gated behind `decorate:` -- same mechanism, same reason, as the
      # slot markers described in "Decoration" below: a builder item's
      # content pane always renders as real DOM regardless (there's no
      # placeholder to synthesize the way an empty PRECISE slot needs one),
      # so gating isn't needed to avoid a divergence risk the way it is
      # there, but it IS needed to keep consistency_spec.rb green --
      # EDITOR_ATTRS there is a small, fixed, hand-typed allowlist of
      # attributes stripped before comparing Renderer's output against
      # ErbGenerator's (`data-editor-node-id`, `data-editor-field`; that
      # spec is deliberately never touched by this feature -- see its own
      # regression guard pinning every fixture render to `decorate: false`),
      # and it does not cover this new attribute. Gating it the same way
      # the slot markers already are keeps it out of every `decorate: false`
      # render path -- consistency_spec.rb's corpus included -- with no
      # change to that spec at all. Distinct attribute name from
      # `data-editor-slot` on purpose: this addresses a (component, builder
      # method) pair, not a (component, slot) one, and the client resolves
      # a hit on it to `{parentId: <the builder item's id>, container:
      # "children"}` rather than a named slot.
      #

      # ## `table`'s :columns is declarative, not callable
      #
      # `table`'s real :columns option needs a `value:` Proc per column
      # (`col[:value].call(row)`, see the component's own partial) -- JSON
      # cannot express a Proc, so a design tree instead carries a
      # declarative `key:` per column and #synthesize_table_columns builds
      # the real callable from it right before dispatch, scoped to exactly
      # `table`'s own :columns option. See that method's doc for the full
      # story, and ErbGenerator#format_columns_array for the export-side
      # counterpart that must stay in agreement with it.
      #
      # ## `table`'s :sort_url is declarative too
      #
      # Same problem, same shape of fix: `table`'s real :sort_url option is
      # a callable (`sort_url.call(key, dir)`), so a design tree carries a
      # declarative Hash instead and #synthesize_sort_url builds the real
      # lambda right before dispatch, scoped to exactly `table`'s own
      # :sort_url option. See that method's doc, SortUrl's own doc, and
      # ErbGenerator#format_sort_url_value for the export-side counterpart.
      #
      # ## Decoration (layout guides) -- off by default, on only when asked
      #
      # `decorate:` (default `false`) turns on a second, independent kind of
      # stamping: "layout guides", ghost outlines the design-editor canvas
      # draws over a slot-style component's own slots so a half-built
      # design's structure stays legible even when a slot is still empty (an
      # empty card is ~2px tall today -- nothing to see, nothing to aim a
      # drag at). See #decorate_slot_opts and #emit_decorated_slots for the
      # two halves of the mechanism, and SlotParts' own module doc for the
      # registry that makes either one possible at all.
      #
      # This is a deliberate, narrow exception to "Renderer only ever
      # reflects the design tree" -- decoration adds attributes/elements the
      # tree itself never asked for. It stays bounded the same way every
      # other exception in this file does: a single `if @decorate` gate,
      # checked at exactly the call sites below and nowhere else, never
      # inverted, never defaulted true anywhere in the codebase.
      # EditorController#preview is the only caller that can ever pass
      # `decorate: true`, and only from a real JSON `true` in the request
      # body (see that controller's own doc) -- every other call site in
      # this codebase (ErbGenerator's consistency corpus, any future caller
      # that just wants real HTML) keeps getting back exactly what it got
      # before this feature existed, unchanged. decoration_spec.rb is the
      # anti-rot check that undecorated output is untouched and decorated
      # output differs from it by exactly SlotParts' declared deltas, no
      # more.
      class Renderer
        MAX_DEPTH = Contract::LIMITS.fetch(:depth)

        # @param view_context [ActionView::Base] a real view context with
        #   TablerUi::Helper mixed in, so `.tabler_ui` resolves
        # @param resolve [#call, nil] takes a partial path String, returns
        #   that file's design tree (a Hash) or nil. Never wired to Rails'
        #   own `render` -- see the class docs' RCE section.
        # @param decorate [Boolean] see the class docs' "Decoration" section
        #   above. Defaults to false, matching every call site that
        #   predates this flag and every one that has no reason to set it.
        def initialize(view_context, resolve: nil, decorate: false)
          @view = view_context
          @resolve = resolve
          @decorate = decorate
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
        #
        # The slot branch's condition is the one place decoration widens
        # what would otherwise happen: undecorated, an all-empty
        # `node["slots"]` skips the block entirely (`node["slots"].present?`
        # false) exactly as before. Decorated, `#decorate_slots_for?` forces
        # the block open even then, because #emit_decorated_slots may still
        # need to hand every known slot a placeholder -- with no block at
        # all there would be no SlotContext to hand one to. See that
        # method's own doc for why this never changes undecorated output
        # (every one of the 13 templates only ever checks
        # `defined?(slots) && slots.present?(:x)`, never `defined?(slots)`
        # alone, so an empty block yields the exact same false either way).
        def render_component_node(node, depth)
          name = node.fetch("name")
          klass = component_class_for(name)
          opts = component_opts(node)

          if klass.respond_to?(:builder_style?) && klass.builder_style?
            opts = synthesize_datagrid_content_marker(name, opts, node["items"])
            @view.tabler_ui.public_send(name, **opts) do |builder|
              emit_items(builder, node["items"], name, :root, depth + 1)
            end
          elsif node["slots"].present? || decorate_slots_for?(name)
            opts = decorate_slot_opts(name, opts, node["id"]) if @decorate
            @view.tabler_ui.public_send(name, **opts) do |slots|
              if @decorate
                emit_decorated_slots(slots, name, node, opts, depth + 1)
              else
                emit_slots(slots, node["slots"], depth + 1)
              end
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
          call_args << builder_item_opts(item, component_name, method_name) unless meth.arity.zero?

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

        # --- Decoration (layout guides, see the class docs) -------------------

        # @return [Boolean] whether #render_component_node should force the
        #   slot-block-yielding branch open even when this node's own
        #   `node["slots"]` is empty -- true only under decoration, and only
        #   for one of SlotMap's 13 known slot-style components. Everything
        #   downstream (#decorate_slot_opts, #emit_decorated_slots) already
        #   no-ops correctly for a component SlotMap doesn't know about
        #   (`SlotMap.slots_for` returns `[]`), so this early, cheap check
        #   exists purely so a fully-empty decorated card/modal/... still
        #   gets a block to hand placeholders to, not to protect anything
        #   downstream from a name it can't handle.
        def decorate_slots_for?(name)
          @decorate && SlotMap.slots_for(name).any?
        end

        # Part (a) of decoration: merges a `data-editor-slot*` marker into
        # the `<part>_html:` (or, for a ROOT_SHARED slot, plain `html:`)
        # option for every slot SlotMap knows about on this component --
        # SlotParts decides where each one lands (see that module's own doc
        # for the three possible answers). Runs once per slot regardless of
        # whether that slot actually has content: on an empty PRECISE slot
        # the placeholder #emit_decorated_slots adds is what makes the
        # marked wrapper exist at all; on a slot the component's own
        # gating never renders in the first place (e.g. table's
        # `filter_form_html:` when `filter:` was never given), the merged
        # Hash entry is simply inert -- the component never calls
        # `html_for(:filter_form, ...)`, so nothing reads it.
        #
        # @return [Hash] opts with zero or more `:html` / `:<part>_html`
        #   entries augmented; every other key untouched.
        def decorate_slot_opts(name, opts, id)
          SlotMap.slots_for(name).each do |slot|
            part = SlotParts.part_for(name, slot)
            next if part == SlotParts::UNMAPPED

            opts =
              if SlotParts.root_shared?(name, slot)
                opts.merge(html: stamp_shared_slot(opts[:html], slot))
              else
                key = :"#{part}_html"
                opts.merge(key => stamp_slot_marker(opts[key], slot, id))
              end
          end
          opts
        end

        # Precise case: the marker lands on the slot's own dedicated
        # wrapper part, together with the owning node's id -- unlike the
        # component's own `html:` (:root) part, a dedicated part carries no
        # id of its own otherwise (#stamp_editor_id only ever stamps
        # :root), so without repeating it here the client would have no way
        # to associate a precise slot guide back to its component. Deep-
        # merges into `data:` the same deliberate way #stamp_editor_id does
        # (see that method's own doc) so a design's own `<part>_html: {
        # data: {...} }` survives and the marker still wins on collision.
        def stamp_slot_marker(html_hash, slot, id)
          html_hash = symbolize(html_hash)
          html_hash.merge(data: symbolize(html_hash[:data]).merge(editor_slot: slot, editor_node_id: id))
        end

        # ROOT_SHARED case: the marker lands on the component's own `html:`
        # (:root) part instead -- the only element in reach for a slot with
        # no dedicated wrapper of its own (see SlotParts::ROOT_SHARED's own
        # doc). Deliberately a DIFFERENT attribute
        # (`data-editor-slot-shared`, never `data-editor-slot`) than the
        # precise case above, so the client can tell a coarse
        # whole-component guide apart from one scoped to a real wrapper
        # without having to know which element either one landed on. No id
        # merged here -- :root already carries `data-editor-node-id`
        # unconditionally via #stamp_editor_id, decorated or not.
        #
        # Joins onto any name(s) already merged rather than overwriting, in
        # case a future component ever maps more than one slot to
        # ROOT_SHARED (none does today -- see SlotParts::PARTS): every
        # shared slot sharing that one coarse guide should stay
        # discoverable from the single attribute.
        def stamp_shared_slot(html_hash, slot)
          html_hash = symbolize(html_hash)
          data = symbolize(html_hash[:data])
          names = data[:editor_slot_shared].to_s.split(",") | [slot.to_s]
          html_hash.merge(data: data.merge(editor_slot_shared: names.join(",")))
        end

        # Part (b) of decoration: renders every SlotMap-known slot for a
        # decorated component -- real content exactly as #emit_slots
        # already would (unaffected by decoration), or, for an EMPTY slot,
        # an inert placeholder just precise enough to flip that slot's
        # `slots.present?(:name)` true so the component's own template
        # stops gating its wrapper element out of existence (every one of
        # these 13 templates does, e.g. card's `<% if ... slots.present?(:body)
        # %>` around `.card-body`). No placeholder for an empty ROOT_SHARED
        # slot -- its region already IS the component root, which always
        # renders regardless, so a placeholder there would only add
        # divergence for no gain (see the class docs) -- and none for a
        # slot #decorated_placeholder_allowed? vetoes.
        #
        # `slots.public_send(slot) { ... }` only ever stores into
        # SlotContext (TablerUi::SlotContext#method_missing); it does not
        # itself decide whether the component ends up rendering that
        # slot's wrapper, real content or placeholder alike -- that stays
        # entirely up to the component's own template. So any exception a
        # template raises reacting to a slot merely being present (avatar's
        # overlay-on-identicon guard is the one case that actually does,
        # and only for slot content a design already supplied -- see
        # #decorated_placeholder_allowed?'s doc for why decoration never
        # synthesizes a placeholder there in the first place) propagates
        # out of this whole method uncaught, straight to #render_node's own
        # per-node `rescue` -- one bad node still becomes one
        # `.alert-danger` marker, not a broken preview.
        def emit_decorated_slots(slots, name, node, opts, depth)
          slot_hash = node["slots"] || {}

          SlotMap.slots_for(name).each do |slot|
            children = slot_hash[slot]
            if children.present?
              slots.public_send(slot) { render_children(children, depth) }
            elsif decorated_placeholder_allowed?(name, slot, opts)
              slots.public_send(slot) { editor_slot_placeholder(slot, node["id"]) }
            end
          end
        end

        # @return [Boolean] whether an empty slot should get a synthesized
        #   placeholder. False for a ROOT_SHARED slot (see
        #   #emit_decorated_slots' own doc), false for an UNMAPPED one
        #   (nothing to place it against at all -- defensive; SlotMap and
        #   SlotParts cover the same slots by construction, kept in sync by
        #   slot_parts_spec.rb), false for table's `filter` slot in either
        #   of the two cases #table_filter_placeholder_allowed? vetoes, and
        #   false for one of the 7 slots #FALLBACK_GUARDED_SLOTS lists when
        #   its own guard says so (see that constant's doc). True for
        #   everything else SlotParts maps to a real, dedicated part.
        def decorated_placeholder_allowed?(name, slot, opts)
          return false if SlotParts.root_shared?(name, slot)
          return false if SlotParts.part_for(name, slot) == SlotParts::UNMAPPED
          return table_filter_placeholder_allowed?(opts) if name == "table" && slot == "filter"

          guard = FALLBACK_GUARDED_SLOTS[[name, slot]]
          return !guard.call(opts) if guard

          true
        end

        # Mirrors, ahead of time and from the very same (already-
        # synthesized) `opts` the real dispatcher call is about to receive,
        # the two conditions under which Table::Component would treat a
        # filter slot as illegitimate:
        #
        # * `table.filter?` (`opts[:filter]` a Hash at all) is false --
        #   the ENTIRE `filter_markup` capture in the template is skipped
        #   (`<% if table.filter? %>`), so a filter slot placeholder would
        #   force a wrapper element into existence the component's own
        #   gating would never otherwise show at all.
        # * `filter:` was given `fields:` (a declarative field list) --
        #   Table::Component#guard_filter_slot! raises the moment BOTH a
        #   filter slot AND `fields:` are present, on the (correct, for a
        #   real design) theory that the two are mutually exclusive ways of
        #   supplying the same toolbar. A design that only ever set
        #   `fields:` and never touched the filter slot renders that
        #   toolbar today with no error at all; decoration synthesizing an
        #   empty placeholder there would flip that same design into a
        #   full-node `.alert-danger` marker purely as a side effect of
        #   turning the flag on -- exactly the kind of large, non-marker
        #   divergence decoration must never introduce.
        #
        # @return [Boolean]
        def table_filter_placeholder_allowed?(opts)
          filter_opt = opts[:filter]
          filter_opt.is_a?(Hash) && filter_opt[:fields].blank?
        end

        # A second family of "must never synthesize a placeholder here",
        # found the same way the class docs say table's filter slot was:
        # by actually reading each template rather than trusting that
        # "empty slot -> add a placeholder" is universally safe. 7 of
        # SlotParts' PRECISE slots don't gate their wrapper on slot
        # presence alone the way card's `body`/`footer` or table's
        # `footer` do (`<% if slots.present?(:x) %>`, nothing else inside
        # to lose) -- they branch `if header_slot ... <REAL fallback
        # content> ... else ... <slot> ... end` (card/modal/toast/
        # offcanvas's `header` falling back to a title; empty's `img`/
        # `icon`/`header` falling back to an illustration/icon/plain
        # text). Flip that branch's condition true via a synthesized
        # placeholder while the fallback content is what a real,
        # undecorated render would show, and the placeholder does not
        # just add a guide marker -- it REPLACES the real, already-visible
        # fallback with an invisible, empty div. Hiding real content is a
        # far larger divergence than decoration is allowed to make (worse
        # than table's case: there, the vetoed placeholder would only have
        # been redundant/unreachable; here, it would actively delete
        # something the reader could already see).
        #
        # `offcanvas`'s `header` is the one entry with two independent
        # fallbacks to protect, not one: unlike card/modal/toast (whose
        # close button, where they have one at all, renders in a separate
        # `if component.close_button` block OUTSIDE the header branch, so
        # is never at risk), offcanvas's own `close_button` -- default
        # `true` when the key is omitted entirely, mirroring
        # Offcanvas::Component#initialize's own
        # `options.key?(:close_button) ? options[:close_button] : true` --
        # sits INSIDE the same `else` branch as its title. Losing the
        # close button to a synthesized placeholder is exactly the
        # regression offcanvas_empty_slots_spec (decoration_spec.rb)
        # caught before this guard existed.
        #
        # Each lambda reads straight from `opts` -- the very same,
        # already-synthesized Hash the real dispatcher call is about to
        # receive -- so it can never drift from what the component itself
        # is about to decide.
        FALLBACK_GUARDED_SLOTS = {
          %w[card header] => ->(opts) { opts[:title].present? },
          %w[modal header] => ->(opts) { opts[:title].present? },
          %w[toast header] => ->(opts) { opts[:title].present? },
          %w[offcanvas header] => lambda { |opts|
            opts[:title].present? || (opts.key?(:close_button) ? !!opts[:close_button] : true)
          },
          %w[empty img] => ->(opts) { opts[:image].present? },
          %w[empty icon] => ->(opts) { opts[:icon].present? },
          %w[empty header] => ->(opts) { opts[:header].present? }
        }.freeze

        # The synthesized placeholder itself: no class, no text, nothing
        # that could be mistaken for real content -- every bit of visible
        # guide styling is drawn client-side, never by this element's own
        # appearance. `aria-hidden="true"` keeps it invisible to assistive
        # tech the same way it already is to sighted users. Carries the
        # same `data-editor-slot`/id pair #stamp_slot_marker puts on the
        # wrapper around it, so the client can identify a placeholder on
        # its own terms without depending on which element the wrapper
        # attributes actually landed on.
        def editor_slot_placeholder(slot, id)
          @view.tag.div(data: { editor_slot: slot, editor_node_id: id }, aria: { hidden: "true" })
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
          opts = synthesize_table_columns(node["name"], opts)
          opts = synthesize_sort_url(node["name"], opts)
          opts.merge(build_html_opts(node["html"], node["id"]))
        end

        # --- table :columns synthesis ------------------------------------

        # A design tree is JSON, so `table`'s :columns can never carry a real
        # `value:` Proc the way hand-written ERB does -- see contract.rb and
        # this file's class docs. The tree instead carries a declarative
        # `key:` per column ("columns" => [{ "label" => "Name", "key" =>
        # "name" }]) and this synthesizes the real `value: ->(row) {
        # row[key] }` the component actually needs, right before dispatch.
        # ErbGenerator#format_columns_array derives the identical lambda,
        # as literal Ruby source, from the same `key:` -- see that method's
        # doc for why the two independently agreeing is the whole point.
        #
        # Scoped to exactly (component == "table", option == :columns) --
        # never applied to an arbitrary Array<Hash> option elsewhere (e.g.
        # datagrid's :items, which has no callable field to synthesize at
        # all: its items are plain title/content pairs).
        def synthesize_table_columns(name, opts)
          return opts unless name == "table" && opts[:columns].is_a?(Array)

          opts.merge(columns: opts[:columns].map { |col| synthesize_column(col) })
        end

        # @param col [Hash] one column entry, already deep-symbolized by
        #   #symbolize/#deep_symbolize above -- a "key"-shaped String key
        #   (matching RUBY_LABEL) has already become the Symbol :key by the
        #   time this runs, exactly like every row Hash under :data has
        #   already had its own String keys turned into Symbols the same
        #   way. #ruby_label_key re-derives a row lookup key by that same
        #   rule, so `row[row_key]` actually finds the row's synthesized
        #   Symbol key rather than missing it against a leftover String.
        # @return [Hash] col unchanged if it already carries a real callable
        #   :value (a caller building a node by hand, bypassing Tree/JSON
        #   entirely, may still pass one); otherwise col with a synthesized
        #   :value and its editor-only :key dropped -- Table::Component
        #   itself has no concept of :key, only :label/:class/:sort/:value,
        #   so leaving :key in would be inert noise on the real dispatcher
        #   call. A raw, non-callable :value (never producible by Tree,
        #   which only lets JSON-shaped values through -- see tree.rb's
        #   #sanitize_generic_value) is likewise discarded rather than ever
        #   being invoked: only #synthesize_column's own key-derived lambda
        #   is ever called, never anything that arrived as a String.
        def synthesize_column(col)
          return col unless col.is_a?(Hash)
          return col if col[:value].respond_to?(:call)

          key = col[:key]
          if key.nil?
            raise ArgumentError, "table column #{col.inspect} has neither key: nor a callable value: -- " \
                                  "nothing to render this cell with"
          end

          row_key = ruby_label_key(key)
          col.except(:key).merge(value: ->(row) { row[row_key] })
        end

        # Mirrors #deep_symbolize's own RUBY_LABEL rule for turning a Hash
        # key into a Symbol -- see that method's doc comment. Applied here
        # to a column's :key *value* (not a Hash key) so the row lookup
        # matches whatever #deep_symbolize already did to the matching key
        # in every row Hash under :data.
        def ruby_label_key(key)
          key_s = key.to_s
          key_s.match?(RUBY_LABEL) ? key_s.to_sym : key_s
        end

        # --- table :sort_url synthesis ------------------------------------

        # Mirrors #synthesize_table_columns for `table`'s other callable
        # option -- see this class's own "table's :sort_url is declarative
        # too" doc, and SortUrl's doc for why the simple-mode-to-pattern
        # conversion happens inside SortUrl.pattern_for rather than here.
        # Tree has already validated the Hash's shape (tree.rb's
        # #normalize_declarative_sort_url); this only builds the lambda the
        # component actually needs, invoked exactly the way the component's
        # own doc comment specifies (`sort_url.call(key, dir)`).
        #
        # Scoped to exactly (component == "table", option == :sort_url) --
        # left untouched (and thus nil/absent, same as a caller who never
        # set it) on any other component or when the tree carries no
        # sort_url: at all, matching #synthesize_table_columns' own guard.
        def synthesize_sort_url(name, opts)
          return opts unless name == "table" && opts[:sort_url].is_a?(Hash)

          pattern = SortUrl.pattern_for(opts[:sort_url])
          opts.merge(sort_url: ->(key, dir) { pattern.sub("{key}", key.to_s).sub("{dir}", dir.to_s) })
        end

        # A builder item's own `html:` hook -- e.g. accordion's `item` takes
        # `html:`/`header_html:`/`body_html:` on itself, same part-keying as
        # a component. `args` is NOT merged in here (unlike #component_opts):
        # a builder item's required value is passed positionally by
        # #emit_item, never inside its options Hash. `component_name`/
        # `method_name` are only used to resolve #stamp_builder_content's
        # own marker -- see that method's doc.
        def builder_item_opts(item, component_name, method_name)
          opts = symbolize(item["options"]).merge(build_html_opts(item["html"], item["id"]))
          stamp_builder_content(opts, component_name, method_name, item["id"])
        end

        # --- Builder-item content-pane stamping (see class docs' "Stamping") --

        # Merges the builder-content marker into whichever `<part>_html:`
        # (or, for BuilderParts::ROOT... see below, plain `:html`) key
        # BuilderParts resolves for this (component_name, method_name) pair
        # -- a no-op for a pair BuilderParts doesn't know about at all
        # (UNMAPPED: not a `block: :children` method, or a component this
        # registry hasn't been told about), for COMPONENT_LEVEL (handled
        # entirely separately, before dispatch -- see
        # #synthesize_datagrid_content_marker -- because the real hook
        # lives on the component, not reachable through a builder item's
        # own options Hash at all), and whenever `@decorate` is false -- see
        # the class docs' "Stamping" section for why this one marker is
        # gated when the id/field stamps around it are not.
        #
        # @return [Hash] opts with zero or one `:html` / `:<part>_html`
        #   entry augmented; every other key untouched.
        def stamp_builder_content(opts, component_name, method_name, id)
          return opts unless @decorate

          part = BuilderParts.part_for(component_name, method_name)
          return opts if part == BuilderParts::UNMAPPED || part == BuilderParts::COMPONENT_LEVEL

          key = part == :root ? :html : :"#{part}_html"
          opts.merge(key => stamp_builder_marker(opts[key], id))
        end

        # A dedicated part (:body, :card, :pane, ...) carries no id of its
        # own otherwise -- unlike the item's own :root/:html part, which
        # #stamp_editor_id already stamps unconditionally -- so this adds
        # BOTH the id and the marker flag, the same "dedicated part needs
        # its own id repeated" reasoning Renderer#stamp_slot_marker already
        # documents for the slot case. For the :root case (carousel), `id`
        # here is the SAME id #stamp_editor_id already wrote into this same
        # Hash moments earlier (both ultimately read item["id"]) -- merging
        # it again is redundant but harmless, and keeps this method's own
        # shape identical regardless of which part it's merging into.
        def stamp_builder_marker(html_hash, id)
          html_hash = symbolize(html_hash)
          html_hash.merge(data: symbolize(html_hash[:data]).merge(editor_node_id: id, editor_builder_content: true))
        end

        # datagrid's `item` is the one BuilderParts::COMPONENT_LEVEL case
        # today (see that constant's own doc for the full reasoning) --
        # Datagrid::Component#item never reads a `content_html:` kwarg at
        # all, so the ordinary per-item route above is a guaranteed no-op
        # for it. Its real `content_html:` hook lives on the component,
        # accepting a Hash (applied identically to every item) or a #call
        # taking the rendered item Hash (`{title:, content:, block:,
        # auth:}` -- no design-tree id of its own). This builds that Proc
        # fresh, right before dispatch, closing over the design tree's own
        # ordered item id list with a monotonically-advancing index --
        # correct because Datagrid::Component#content_attributes(item) is
        # called exactly once per item, in the SAME order @items were
        # appended, which is the SAME order `node["items"]` lists them in:
        # every item posted through the editor is authorized by
        # construction (`auth:` is stripped from the whole editor surface --
        # see the class docs' RCE section's sibling concern, rule 8/9's
        # `auth:` strip), so there is no filtering discrepancy that could
        # desync the two orderings. Mirrors #synthesize_table_columns'/
        # #synthesize_sort_url's own "build the real callable the component
        # needs, right before dispatch, scoped to exactly one (component,
        # option) pair" shape.
        #
        # Gated on `@decorate`, same as #stamp_builder_content -- see the
        # class docs' "Stamping" section.
        #
        # @return [Hash] opts unchanged for any component other than
        #   datagrid, or whenever `@decorate` is false; opts with
        #   :content_html set to the synthesized Proc otherwise
        #   (overwriting any :content_html a design's own component-level
        #   options carried -- a design posted through the editor has no
        #   way to author a real Proc there in the first place, so there is
        #   nothing legitimate to preserve).
        def synthesize_datagrid_content_marker(name, opts, items)
          return opts unless @decorate && BuilderParts.component_level?(name, "item")

          ids = Array(items).map { |item| item["id"] }
          index = -1
          marker = lambda do |_item|
            index += 1
            id = ids[index]
            id ? { data: { editor_node_id: id, editor_builder_content: true } } : {}
          end
          opts.merge(content_html: marker)
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
