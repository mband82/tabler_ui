# frozen_string_literal: true

module TablerUi
  module Docs
    module Editor
      # Registry of how a design-editor "content pane" -- the element a
      # BUILDER item's own block content (`accordion.item("x") { ... }`,
      # `tabs.tab("x") { ... }`) actually renders into -- can be reached at
      # all, for the same two reasons SlotParts already exists for
      # slot-style components: (1) a canvas drag needs to know which
      # element to stamp a marker onto so a drop can resolve straight
      # "into" that item's own `children`, and (2) a layout guide needs the
      # same element to draw its outline against. See SlotParts' own module
      # doc for the mechanism this reuses (merge a marker attribute into a
      # component's own `html:` / `<part>_html:` hook); this module answers
      # the builder-item version of the same question SlotParts answers for
      # slots: which `<part>_html:` -- if any -- wraps a *particular
      # builder item's* own content.
      #
      # Scope: every `(component, method)` pair BuilderMap records with
      # `block: :children` -- a builder method whose block is the item's OWN
      # content, as opposed to `block: :items` (yields a further nested
      # builder, e.g. navbar's `left`/`right`) or `block: nil` (no block at
      # all, e.g. `breadcrumb.item`, `dropdown.divider`). Only a
      # `:children` method ever has a "content pane" for a guide/drop to
      # reach in the first place.
      #
      # Each of the three possible answers below was verified by hand, one
      # component at a time, the same way SlotParts' were: reading the
      # builder method's own doc comment/struct fields (does IT accept a
      # per-item `<x>_html:` hook that reaches the content wrapper?) and the
      # template (does that hook's part actually wrap the block's captured
      # content, or something else?):
      #
      # * The common case: the item's content sits inside a dedicated part
      #   the builder method's OWN per-item `<x>_html:` kwarg already
      #   reaches (accordion's `body_html:` -> part :item_body, timeline's
      #   `card_html:` -> part :card) -- recorded here as the SUFFIX of
      #   that kwarg name (:body, :card), matching the vocabulary
      #   Renderer#build_html_opts already uses for a builder item's own
      #   `item["html"]` parts ("root" -> :html, anything else ->
      #   "#{part}_html"). settings_page's `item` and tabs' `tab` are two
      #   more instances of exactly this shape, added by this same task --
      #   their new `pane_html:` kwarg is what #stamp_builder_content
      #   below now has a hook name to target.
      # * ROOT: carousel's `item` has no separate content wrapper at all --
      #   its `.carousel-item` (part :item, reached by the SAME `html:`
      #   kwarg #stamp_editor_id already stamps unconditionally for every
      #   builder item's own root) IS where the slide's content renders.
      #   Recorded as :root -- Renderer already builds a `:html` entry for
      #   every builder item regardless, so this tells
      #   #stamp_builder_content to merge into that SAME hash rather than a
      #   second, separate `<part>_html:` key.
      # * COMPONENT_LEVEL: datagrid's `.datagrid-content` wrapper IS backed
      #   by a real hook (`content_html:`, part :content) -- but unlike
      #   every other entry here, that hook lives on the *component*,
      #   supplied once at construction (`tabler_ui.datagrid(content_html:
      #   ...)`), not per call to `#item`. `Datagrid::Component#item(title,
      #   options = {})` only ever reads `options[:content]` -- a
      #   `content_html:` kwarg passed to an individual `dg.item(...)` call
      #   is silently discarded (`initialize_html_options` only runs once,
      #   at `#initialize`). So the ordinary per-item route
      #   (#stamp_builder_content, threaded through
      #   Renderer#builder_item_opts exactly like every other entry above)
      #   is a guaranteed no-op for this one pair -- reaching it needs a
      #   *component-level* `content_html:` built fresh, before dispatch,
      #   from the design tree's own item order
      #   (Renderer#synthesize_datagrid_content_marker). COMPONENT_LEVEL
      #   marks that this pair needs that different code path instead of
      #   the generic one, exactly the way SlotParts::ROOT_SHARED marks
      #   "this slot's answer needs different handling downstream", not a
      #   real per-item part name.
      #
      # Hand-maintained, not derived at load time -- same reasoning as
      # SlotParts and BuilderMap: docs/lib is on $LOAD_PATH but is NOT
      # Zeitwerk-autoloaded and NOT reloaded in development, so a constant
      # re-derived on every load would only ever reflect server-boot state
      # anyway, and editing this file already requires a restart regardless.
      #
      # spec/lib/tabler_ui/docs/editor/builder_parts_spec.rb re-derives this
      # same judgement at runtime -- for every `block: :children` pair
      # BuilderMap records, by walking the component's own template to find
      # which part wraps the item's captured content (mirroring SlotParts'
      # own template-walking algorithm, keyed to `capture(&item.content)`/
      # `capture(&item[:block])` instead of `slots.<name>`), then reading
      # component.rb to translate that internal part into the outward
      # `<x>_html:` kwarg name (or COMPONENT_LEVEL, when no per-item
      # reassignment of that part exists anywhere in the file) -- and
      # asserts it against PARTS below, plus asserts PARTS covers exactly
      # the same `(component, method)` pairs BuilderMap marks `block:
      # :children`. Keep that spec green rather than patching around a
      # failure; a failure there means PARTS is wrong, not the spec.
      module BuilderParts
        # Sentinel returned by .part_for for a `(component, method)` pair
        # this registry has no entry for -- an unknown component/method, or
        # a `block:` other than `:children` (nothing to reach at all: see
        # the module doc's "Scope"). Always a Symbol, like every other
        # value here, so a caller never needs a nil-guard before comparing
        # the result.
        UNMAPPED = :unmapped

        # Sentinel part value for the COMPONENT_LEVEL case described in the
        # module doc above (datagrid's `item` -> :content, today) -- a real
        # hook exists, but it is not reachable through the generic per-item
        # route #stamp_builder_content uses for every other entry. Never a
        # real part name a template could expose: `html_for`'s part
        # namespace belongs to each component's own parts (:body, :card,
        # :content, ...), and "component_level" collides with none of them.
        COMPONENT_LEVEL = :component_level

        # component name => { method name => part Symbol }. A part Symbol
        # is either the outward `<x>_html:` kwarg name (minus its `_html`
        # suffix) a builder method's own per-item hook already uses
        # (:body, :card, :pane), :root for the one case where a builder
        # item's OWN root part is already its content wrapper (carousel),
        # or COMPONENT_LEVEL (datagrid) -- see the module doc's three
        # bullets for the full reasoning behind each.
        #
        # Keys sorted alphabetically, matching SlotParts' own convention,
        # so this diffs deterministically.
        PARTS = {
          "accordion" => { "item" => :body }.freeze,
          "carousel" => { "item" => :root }.freeze,
          "datagrid" => { "item" => COMPONENT_LEVEL }.freeze,
          "settings_page" => { "item" => :pane }.freeze,
          "tabs" => { "tab" => :pane }.freeze,
          "timeline" => { "item" => :card }.freeze
        }.freeze

        module_function

        # @param component [String, Symbol] a component name (its directory
        #   name under app/components/tabler_ui, e.g. "accordion")
        # @param method [String, Symbol] a builder method name on that
        #   component (e.g. "item", "tab")
        # @return [Symbol] the part to merge a builder-content marker's
        #   attributes into -- a real per-item `<x>_html:` part name,
        #   :root, COMPONENT_LEVEL, or UNMAPPED. Never nil, never raises.
        def part_for(component, method)
          PARTS.dig(component.to_s, method.to_s) || UNMAPPED
        end

        # @param component [String, Symbol]
        # @param method [String, Symbol]
        # @return [Boolean] whether this pair needs the COMPONENT_LEVEL
        #   code path (Renderer#synthesize_datagrid_content_marker) rather
        #   than the generic per-item one (#stamp_builder_content). False
        #   for an UNMAPPED pair too -- there is no marker, generic or
        #   otherwise, for a pair this registry doesn't know about.
        def component_level?(component, method)
          part_for(component, method) == COMPONENT_LEVEL
        end
      end
    end
  end
end
