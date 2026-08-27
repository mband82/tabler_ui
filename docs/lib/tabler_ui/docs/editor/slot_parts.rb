# frozen_string_literal: true

module TablerUi
  module Docs
    module Editor
      # Registry of how a design-editor "layout guide" -- a ghost outline
      # drawn over one of a component's slots on the WYSIWYG canvas -- can
      # reach that slot at all. The mechanism itself is the same rule-5 HTML
      # hook Renderer#stamp_editor_id already uses for the root node: merge a
      # marker attribute into the component's own `html:` / `<part>_html:`
      # option, and the component renders that attribute onto whichever
      # element the option is wired to. `data-editor-slot="body"` would go
      # into `body_html:` the same way `data-editor-node-id` already goes
      # into `html:`.
      #
      # What that mechanism can NOT tell you is which `<part>_html:` -- if
      # any -- actually wraps a *particular slot's* rendered content. Slot
      # names come from SlotMap (`slots.body`, `slots.header`, ...); part
      # names come from each component's own `initialize_html_options` /
      # `html_for` calls (`:body`, `:header`, ...); nothing in
      # TablerUi::Base, SlotContext, or the dispatcher requires the two
      # vocabularies to line up, or requires a slot to have a dedicated
      # wrapper element at all. Each of the three possible answers below was
      # verified by hand, one component at a time, by reading its
      # `component.rb` (which parts does `html_for` actually expose?) and
      # its `_component.html.erb` (does that part's attributes land on the
      # element that directly wraps this slot's content, on some other
      # element, or nowhere near it?) -- there is no shared code path that
      # would let this be derived generically at runtime:
      #
      # * Usually a slot's own name doubles as a `<part>_html:` hook, and
      #   that hook's attributes land on the element that directly wraps the
      #   slot's content (card's `body` slot / `body_html:` / `.card-body`).
      #   This is the common case, but it is a coincidence of how each
      #   template happened to be written, not a guarantee.
      # * table's `filter` slot is a name MISMATCH: its content renders
      #   straight into the `<form>`, which is the `filter_form` part --
      #   `filter` itself only names the toolbar's *outer* wrapper div, one
      #   level further out than the slot's own content.
      # * A handful of slots -- alert's `body`, avatar's `overlay`,
      #   badge_list's `body`, card_group's `body`, ribbon's `body` -- have
      #   no dedicated wrapper at all: their content renders straight into
      #   the component's own root element (or, for alert, into a plain
      #   inner `<div>` that itself carries no hook of its own, which comes
      #   to the same thing -- nothing between that `<div>` and the root
      #   carries an attribute). The nearest thing a guide marker CAN land
      #   on for one of these is the component's own `html:` hook (part
      #   :root) -- the same element #stamp_editor_id already marks for the
      #   whole component. A guide built from that is deliberately coarser
      #   than a dedicated-part guide: the outline drawn covers the *entire
      #   component*, not just that slot's own region within it, because the
      #   root element is the only thing in reach that carries an attribute
      #   at all. See ROOT_SHARED below.
      #
      # Hand-maintained, not derived at load time, for the same reason
      # SlotMap is (see its module doc for the full argument): docs/lib is
      # on $LOAD_PATH but is NOT Zeitwerk-autoloaded and NOT reloaded in
      # development, so a constant that re-derived this at every load would
      # only ever reflect server-boot state anyway, and editing this file
      # already requires a restart regardless. Plain frozen constant module,
      # no per-request mutable state.
      #
      # spec/lib/tabler_ui/docs/editor/slot_parts_spec.rb re-derives this
      # same judgement at runtime -- by walking each template's actual
      # element/block nesting to find, for every `slots.<name>` reference,
      # the nearest enclosing element whose attributes come from a
      # `html_for`-backed part -- and asserts it against PARTS below, plus
      # asserts PARTS covers exactly the same components/slots SlotMap::SLOTS
      # does, so the two registries cannot silently drift apart. Keep that
      # spec green rather than patching around a failure; a failure there
      # means PARTS is wrong, not the spec.
      module SlotParts
        # Sentinel part value for a slot with no dedicated wrapper of its
        # own -- see the module doc's third bullet. A guide for a slot
        # mapped to ROOT_SHARED has to be drawn against the component's
        # `html:` hook (part :root), the same element the component's own
        # node marker uses, and is therefore, by necessity, the coarse
        # whole-component outline rather than one scoped to just that
        # slot's region.
        #
        # Never a real part name: `html_for`'s part namespace belongs to
        # each component's own parts (:body, :header, :filter_form, ...),
        # and none of them is named "root_shared", so this can't collide
        # with a genuine dedicated part.
        ROOT_SHARED = :root_shared

        # Sentinel returned by .part_for for a (component, slot) pair this
        # registry simply has no entry for -- an unknown component, an
        # unknown slot, or a typo of either. Distinct from ROOT_SHARED,
        # which means "this slot IS known, and its answer is the coarse
        # one" -- UNMAPPED means "no answer at all, not even a coarse one."
        # Always a Symbol, like every other value here, so a caller never
        # needs a nil-guard before comparing the result.
        UNMAPPED = :unmapped

        # Component name => { slot name => part Symbol }. A part Symbol is
        # either a real `html_for` part on that component (e.g. :body,
        # :header, :filter_form) or ROOT_SHARED. Only the 13 components
        # SlotMap::SLOTS lists appear here, with exactly the same slot
        # names per component -- spec/lib/tabler_ui/docs/editor/
        # slot_parts_spec.rb asserts that coverage stays exact.
        #
        # Keys sorted alphabetically, and slot names within each component
        # sorted alphabetically, matching SlotMap's own convention, so this
        # diffs deterministically regardless of the order slots happen to
        # appear in a template.
        PARTS = {
          "alert" => { "body" => ROOT_SHARED }.freeze,
          "avatar" => { "overlay" => ROOT_SHARED }.freeze,
          "badge_list" => { "body" => ROOT_SHARED }.freeze,
          "card" => { "body" => :body, "footer" => :footer, "header" => :header }.freeze,
          "card_group" => { "body" => ROOT_SHARED }.freeze,
          "dimmer" => { "content" => :content }.freeze,
          "empty" => { "action" => :action, "header" => :header, "icon" => :icon, "img" => :img }.freeze,
          "modal" => { "body" => :body, "footer" => :footer, "header" => :header }.freeze,
          "offcanvas" => { "body" => :body, "footer" => :footer, "header" => :header }.freeze,
          "page_header" => { "buttons" => :buttons }.freeze,
          "ribbon" => { "body" => ROOT_SHARED }.freeze,
          "table" => { "filter" => :filter_form, "footer" => :footer }.freeze,
          "toast" => { "body" => :body, "header" => :header }.freeze
        }.freeze

        module_function

        # @param component [String, Symbol] a component name (its directory
        #   name under app/components/tabler_ui, e.g. "card")
        # @param slot [String, Symbol] a slot name on that component (e.g. "body")
        # @return [Symbol] the part to merge a guide marker's attributes
        #   into -- a real `html_for` part name, ROOT_SHARED when the slot
        #   has no dedicated wrapper (see the module doc), or UNMAPPED when
        #   this registry has no entry for the pair at all. Never nil,
        #   never raises, so callers don't need to special-case an unknown
        #   component/slot before comparing the result.
        def part_for(component, slot)
          PARTS.dig(component.to_s, slot.to_s) || UNMAPPED
        end

        # @param component [String, Symbol]
        # @param slot [String, Symbol]
        # @return [Boolean] whether this slot's guide is necessarily the
        #   coarse, whole-component outline (see ROOT_SHARED) rather than
        #   one scoped to a dedicated wrapper. False for an UNMAPPED pair
        #   too -- there is no guide, coarse or otherwise, to draw for a
        #   slot this registry doesn't know about.
        def root_shared?(component, slot)
          part_for(component, slot) == ROOT_SHARED
        end
      end
    end
  end
end
