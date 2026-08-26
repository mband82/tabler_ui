# frozen_string_literal: true

module TablerUi
  module Docs
    module Editor
      # Registry linking an option *name* (e.g. "color", "align") to the
      # fixed set of values it actually accepts, for whichever component it
      # appears on.
      #
      # This exists because a component option that's validated at runtime
      # (raises ArgumentError on an unknown value -- see TablerUi::Color,
      # TablerUi::Align, TablerUi::Position, TablerUi::Breakpoint, and each
      # component's own private `validate_*!`) only records its valid values
      # in two places today: the raise message itself, and English prose in
      # the `@option` doc comment. Neither is machine-readable. A future
      # design-editor property panel needs to render a `<select>` of real
      # values instead of a free-text box that round-trips into
      # ArgumentError -- this module is that link.
      #
      # docs/lib is on $LOAD_PATH (gemspec require_paths) but is NOT
      # Zeitwerk-autoloaded and NOT reloaded in development -- same as every
      # other file under docs/lib/tabler_ui/docs (see navigation.rb,
      # doc_parser.rb). Every constant this file touches needs an explicit
      # `require` at the call site (this file itself requires nothing extra:
      # TablerUi::Color/Align/Position/Breakpoint and every
      # TablerUi::<X>::Component class live under the gem's own
      # app/components + lib trees, which ARE Zeitwerk-autoloaded by the
      # main engine -- only docs/lib's own files need explicit requiring),
      # and editing this file requires a server restart in the docs app.
      # Hold no per-request mutable state -- see GLOBAL/PER_COMPONENT below,
      # both plain frozen Hashes.
      #
      # ## Why the values are lambdas, not literal arrays
      #
      # `TablerUi::Color::ALL` etc. can change shape over time (a new brand
      # colour, a renamed breakpoint). A literal copy here
      # (`%w[blue azure ...]`) would silently drift the moment the real
      # constant changed -- exactly the failure mode `Navigation::CATEGORIES`
      # guards against for the component list, and `SlotMap::SLOTS` guards
      # against for slot names. Both of those are hand-derived snapshots
      # re-checked by a spec; a *value list* has no such derivation to
      # re-run (there's no "grep every valid color out of color.rb"), so the
      # safer shape here is a reference that re-reads the real constant
      # every time it's resolved: `-> { TablerUi::Color::ALL }`, not
      # `TablerUi::Color::ALL.dup`. #values_for calls the lambda at lookup
      # time, so a later change to Color::ALL (or BRAND, or any per-component
      # local constant referenced below) is picked up immediately -- no
      # separate sync step, nothing to forget.
      #
      # ## GLOBAL vs. PER_COMPONENT
      #
      # GLOBAL covers option *names* whose value list is the same everywhere
      # that name appears (color/align/position/breakpoint -- see
      # TablerUi::Color/Align/Position/Breakpoint). PER_COMPONENT covers a
      # (component, option) pair whose accepted values are either narrower
      # than GLOBAL's set for the same name (e.g. steps' `color:` only takes
      # TablerUi::Color::TABLER, not the full palette+semantic ALL; ribbon's
      # `position:` only takes Position::VERTICAL, not all four EDGES) or
      # wider (button's `color:` adds BRAND + MUTED on top of ALL), or an
      # entirely different vocabulary local to that one component (dropdown's
      # `direction:`, toast's `position:`, ...). #values_for checks
      # PER_COMPONENT first and returns its list outright when present --
      # PER_COMPONENT never merges with GLOBAL, it replaces it for that one
      # (component, option) pair. A component/option combination present in
      # neither falls back to nil, not an empty Array, so a caller can tell
      # "no enum here" apart from "enum with no values" (which shouldn't
      # exist, but nil is still the more honest signal of "not registered").
      #
      # ## The `symbol:` flag
      #
      # JSON (what a browser property panel actually receives) has no Symbol
      # type, so #values_for always resolves to an Array<String> regardless
      # of whether the real component reads the value back as a String or a
      # Symbol. `symbol:` records which one the component's own `validate!`
      # (module-level, e.g. TablerUi::Align.validate!) or its own private
      # `validate_*!` actually returns, so a caller sending a value back to
      # Ruby knows whether to `.to_sym` it first -- e.g. dropdown's
      # `align:` (TablerUi::Align.validate!) wants `:end`, not `"end"`.
      #
      # ## Only real, verified links
      #
      # Every entry below was confirmed by reading the referenced
      # component's own source: the exact option name in its `@option`
      # block, and (where one exists) the `validate!`/`validate_*!` call
      # that actually raises ArgumentError for a value outside the list.
      # Two components' entries below (badge's `size:`, illustration's
      # `size:`) are option names with a real, confirmed fixed value set
      # that is NOT raise-validated -- badge's `validate_size` silently
      # returns nil for an unrecognised value instead of raising, and
      # illustration's `size:` falls back to `.to_i` on an unrecognised
      # value. They're included anyway (a property panel still wants a
      # `<select>` for them) but spec/lib/tabler_ui/docs/editor/enum_map_spec.rb
      # skips the "survives validate!" assertion for those two specifically,
      # with a comment saying why, rather than pretending a raise exists.
      # Same story for placeholder's `ratio:`, `type:` and `animation:`.
      #
      # ## Deliberately excluded
      #
      # `table`'s `sort:` (`{ key:, dir: }`) and `filter:`
      # (`{ method:, fields: [...], ... }`) options each carry their own
      # small enum internally (SORT_DIRS, FILTER_METHODS) but those live
      # *inside* a Hash-shaped option, not as `table`'s own flat
      # `@option options [String] :dir`-style entry -- DocParser only
      # recovers the outer option name ("sort", "filter"), so there is no
      # (component, option) pair here that could ever match them under this
      # module's flat (component, option) -> values shape. Recovering
      # nested/per-field option shapes (this, and a dropdown/carousel/etc.
      # item's own builder-method options) is a parallel task's concern --
      # see DocParser#builder_options and the note on assertion 2 in the
      # spec file.
      module EnumMap
        # Option name => resolver, for names whose accepted values are the
        # same on every component that exposes them.
        GLOBAL = {
          "color" => { values: -> { TablerUi::Color::ALL }, symbol: false }.freeze,
          "align" => { values: -> { TablerUi::Align::VALID }, symbol: true }.freeze,
          "position" => { values: -> { TablerUi::Position::EDGES }, symbol: true }.freeze,
          "breakpoint" => { values: -> { TablerUi::Breakpoint::ALL }, symbol: false }.freeze
        }.freeze

        # Component name => { option name => resolver }, for (component,
        # option) pairs whose accepted values are narrower, wider, or simply
        # different from GLOBAL's entry for the same option name -- or that
        # have no GLOBAL entry at all. See the module docs above for the
        # override rule (#values_for never merges the two).
        PER_COMPONENT = {
          "button" => {
            # extra: BRAND + MUTED -- Tabler defines .btn-<brand> and
            # .btn-muted, with no bg-/text- equivalents, so only buttons
            # accept these on top of the general palette (see
            # button/component.rb's own :color option doc and
            # TablerUi::Color::BRAND / ::MUTED).
            "color" => {
              values: -> { TablerUi::Color::ALL + TablerUi::Color::BRAND + TablerUi::Color::MUTED },
              symbol: false
            }.freeze,
            "animate_icon" => {
              values: -> { TablerUi::Button::Component::ANIMATE_ICON_MODIFIERS },
              symbol: false
            }.freeze
          }.freeze,
          "alert" => {
            # extra: MUTED only -- alert has no brand-colour styling.
            "color" => { values: -> { TablerUi::Color::ALL + TablerUi::Color::MUTED }, symbol: false }.freeze,
            "link_style" => { values: -> { TablerUi::Alert::Component::LINK_STYLES }, symbol: true }.freeze
          }.freeze,
          "card" => {
            "status_position" => { values: -> { TablerUi::Card::Component::STATUS_POSITIONS }, symbol: false }.freeze
            # "status" (the strip's colour) is plain TablerUi::Color::ALL,
            # no extra -- matches GLOBAL's "color" entry, so no override here.
          }.freeze,
          "badge" => {
            # NOT raise-validated -- Badge::Component#validate_size silently
            # returns nil for a value outside SIZES rather than raising. See
            # the module docs' "Only real, verified links" note; the spec
            # skips the "survives validate!" assertion for this entry.
            "size" => { values: -> { TablerUi::Badge::Component::SIZES }, symbol: false }.freeze
          }.freeze,
          "placeholder" => {
            # Raise-validated (Placeholder::Component#validate_size!), but
            # only when type: isn't :avatar -- avatar uses its own, larger
            # .avatar-* scale instead. The spec instantiates with an
            # explicit non-avatar type: to exercise the real raise.
            "size" => { values: -> { TablerUi::Placeholder::Component::SIZES }, symbol: false }.freeze,
            # ratio:/type:/animation: are real, confirmed option names with
            # a genuine fixed value set, but NONE of the three raise on an
            # unrecognised value (ratio_class falls back to "ratio-21x9";
            # type has no validation at all and falls through to the
            # default/fallback rendering path; has_animation? just checks
            # inclusion and no-ops otherwise) -- see the module docs' "Only
            # real, verified links" note.
            "ratio" => { values: -> { TablerUi::Placeholder::Component::RATIOS }, symbol: false }.freeze,
            "type" => { values: -> { TablerUi::Placeholder::Component::TYPES }, symbol: true }.freeze,
            "animation" => { values: -> { TablerUi::Placeholder::Component::ANIMATIONS }, symbol: true }.freeze
          }.freeze,
          "page_header" => {
            "title_size" => { values: -> { TablerUi::PageHeader::Component::TITLE_SIZES }, symbol: false }.freeze
          }.freeze,
          "toast" => {
            "position" => { values: -> { TablerUi::Toast::Component::POSITIONS }, symbol: false }.freeze
          }.freeze,
          "dropdown" => {
            # DIRECTIONS is a Hash of "option value" => "wrapper CSS class"
            # (e.g. "up" => "dropup") -- the valid *values for direction:*
            # are the keys, not the values. align:/align_breakpoint: are not
            # overridden here: both use the full GLOBAL vocabulary (Align::VALID,
            # Breakpoint::ALL) unchanged, so GLOBAL's own "align"/"breakpoint"
            # entries already cover them.
            "direction" => { values: -> { TablerUi::Dropdown::Component::DIRECTIONS.keys }, symbol: false }.freeze
          }.freeze,
          "ribbon" => {
            # Narrower than GLOBAL's "position" (all four EDGES) -- a ribbon
            # only sits on the top or bottom edge, per
            # TablerUi::Position::VERTICAL and ribbon/component.rb's own
            # `allowed: TablerUi::Position::VERTICAL` call.
            "position" => { values: -> { TablerUi::Position::VERTICAL }, symbol: true }.freeze
            # align: uses the full Align::VALID set unchanged -- covered by
            # GLOBAL's "align" entry, no override needed.
          }.freeze,
          "illustration" => {
            # SIZES is a Hash keyed by Symbol (xs/sm/md/lg/xl/xxl => pixel
            # width) -- valid values for size: are the keys. NOT
            # raise-validated: an unrecognised size: falls back to
            # `.to_i` (see Illustration::Component#sized_dimensions) rather
            # than raising. Spec skips the "survives validate!" assertion.
            "size" => { values: -> { TablerUi::Illustration::Component::SIZES.keys }, symbol: true }.freeze
          }.freeze,
          "modal" => {
            "size" => { values: -> { TablerUi::Modal::Component::SIZES }, symbol: false }.freeze
          }.freeze,
          "steps" => {
            # Narrower than GLOBAL's "color" -- steps only accepts the
            # Tabler palette (TABLER), not the Bootstrap semantic names
            # (SEMANTIC) the rest of ALL adds in. See
            # steps/component.rb#validate_color!.
            "color" => { values: -> { TablerUi::Color::TABLER }, symbol: false }.freeze
          }.freeze,
          "breadcrumb" => {
            "style" => { values: -> { TablerUi::Breadcrumb::Component::STYLES }, symbol: true }.freeze
          }.freeze,
          "spinner" => {
            "type" => { values: -> { TablerUi::Spinner::Component::TYPES }, symbol: true }.freeze
            # color: is plain TablerUi::Color::ALL, no extra -- covered by
            # GLOBAL, no override here.
          }.freeze,
          "tabs" => {
            "style" => { values: -> { TablerUi::Tabs::Component::STYLES }, symbol: true }.freeze
          }.freeze,
          "pagination" => {
            "size" => { values: -> { TablerUi::Pagination::Component::SIZES }, symbol: true }.freeze
          }.freeze,
          "carousel" => {
            # indicators: is actually a tri-state Boolean|Symbol option
            # (true/false/one of INDICATOR_VARIANTS) -- only the Symbol
            # variant values are listed here; a property panel would pair
            # this enum with a separate on/off control for the boolean
            # cases. See Carousel::Component#validate_indicators!.
            "indicators" => { values: -> { TablerUi::Carousel::Component::INDICATOR_VARIANTS }, symbol: true }.freeze
          }.freeze
        }.freeze

        module_function

        # @param component [String, Symbol] a component name, e.g. "button"
        # @param option [String, Symbol] an option name, e.g. "color"
        # @return [Hash, nil] the raw `{ values:, symbol: }` entry
        #   (PER_COMPONENT's, if one exists for this exact pair, otherwise
        #   GLOBAL's for this option name -- never both, never merged), or
        #   nil if neither has an entry for it.
        def entry_for(component, option)
          PER_COMPONENT.dig(component.to_s, option.to_s) || GLOBAL[option.to_s]
        end

        # @param component [String, Symbol] a component name, e.g. "button"
        # @param option [String, Symbol] an option name, e.g. "color"
        # @return [Array<String>, nil] every accepted value, resolved from
        #   the entry's lambda at call time (so a later change to the
        #   underlying constant -- TablerUi::Color::ALL gaining a colour, a
        #   component's own local SIZES constant changing -- is picked up
        #   immediately) and stringified uniformly regardless of whether the
        #   real component reads Strings or Symbols back (see #symbol? for
        #   that bookkeeping). nil when neither PER_COMPONENT nor GLOBAL has
        #   an entry for this (component, option) pair.
        def values_for(component, option)
          entry = entry_for(component, option)
          return nil unless entry

          entry[:values].call.map(&:to_s)
        end

        # @param component [String, Symbol] a component name, e.g. "dropdown"
        # @param option [String, Symbol] an option name, e.g. "align"
        # @return [Boolean, nil] whether the component reads this value back
        #   as a Symbol (true) or a String (false) -- a caller sending a
        #   value from #values_for back into Ruby uses this to decide
        #   whether to `.to_sym` it first. nil when neither PER_COMPONENT
        #   nor GLOBAL has an entry for this (component, option) pair.
        def symbol?(component, option)
          entry_for(component, option)&.fetch(:symbol)
        end
      end
    end
  end
end
