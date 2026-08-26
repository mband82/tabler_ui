# frozen_string_literal: true

module TablerUi
  module Docs
    module Editor
      # Registry of every builder method the 11 `builder_style!` components
      # (see `TablerUi::Base::ClassMethods#builder_style!`,
      # lib/tabler_ui/base.rb) expose for adding sub-items -- `tabs.tab`,
      # `dropdown.item`, `navbar.left { |nav| nav.add ... }`, etc. The
      # design editor's visual palette uses this to know, for a component
      # dropped on the canvas, which "add a sub-item" buttons to offer, what
      # to label the item's mandatory field, and whether adding one opens a
      # nested builder (a navbar dropdown) or just takes freeform content (a
      # tab's body).
      #
      # Hand-maintained, not derived at load time -- same reasoning as
      # docs/lib/tabler_ui/docs/navigation.rb's CATEGORIES and
      # docs/lib/tabler_ui/docs/editor/slot_map.rb's SLOTS: docs/lib is on
      # $LOAD_PATH (gemspec require_paths) but is NOT Zeitwerk-autoloaded and
      # NOT reloaded in development, so a constant that re-parsed the
      # component sources on every load would only ever reflect the state at
      # server boot -- editing *this* file already requires a server restart
      # regardless, so deriving BUILDERS dynamically would buy nothing at
      # runtime, only cost. It's a plain frozen constant module: no
      # per-request mutable state, no methods that mutate anything, safe to
      # hold across requests.
      #
      # Derived by hand by reading every file under
      # app/components/tabler_ui/{datagrid,dropdown,timeline,breadcrumb,
      # steps,tabs,pagination,carousel,settings_page,navbar,accordion}/ in
      # full (`grep -rl "builder_style!" app/components/tabler_ui/` finds
      # exactly these 11). spec/lib/tabler_ui/docs/editor/builder_map_spec.rb
      # re-derives the checkable parts of this at runtime via reflection
      # (method existence, first required positional parameter) and asserts
      # equality against BUILDERS below -- keep that spec green rather than
      # patching around a failure; a failure there means BUILDERS is wrong,
      # not the spec.
      #
      # `auth:` (CLAUDE.md rule 8's per-item authorization option, added to
      # every one of these builder methods) is deliberately NOT recorded
      # anywhere below -- it is never the "mandatory positional arg" (it is
      # always an `options[:auth]` key, never positional) and it is not a
      # sub-item-adding method in its own right, so it has no entry of its
      # own either.
      #
      # ## Shape
      #
      # BUILDERS is `{ component_name => { level_name => { method_name =>
      # descriptor } } }`.
      #
      # `component_name` is a String matching the component's directory name
      # under app/components/tabler_ui (same vocabulary as
      # TablerUi::Docs::Navigation.components).
      #
      # `level_name` is a Symbol. Every component here has a `:root` level --
      # the methods callable directly on the object the caller's block is
      # yielded (`tabs.tab`, `dropdown.item`). `navbar` is the one exception,
      # with two further levels reached by nesting one builder inside
      # another (see "navbar's levels" below) -- `:group` and `:dropdown`.
      # Modeling every component as "one or more named levels" (rather than
      # giving navbar special-cased fields) means a generic reader can walk
      # any component here the same way: start at `:root`, and whenever a
      # method descriptor carries `block: :items`, follow its `nests:` key
      # to find the next level's method Hash -- no `if component == "navbar"`
      # anywhere in that walk.
      #
      # A method descriptor is a Hash:
      #   klass: [String] the class the method is defined on, relative to
      #     "TablerUi::<CamelizedComponentName>::" -- i.e. the full constant
      #     is "TablerUi::#{component_name.camelize}::#{klass}". Always
      #     "Component" for a :root-level method. Navbar's nested levels
      #     point at "Component::NavigationGroup" (:group) and
      #     "Component::NavigationGroup::DropDownProxy" (:dropdown) -- both
      #     are classes nested *inside* Navbar::Component in the source, not
      #     siblings of it (confirmed by matching every `class`/`end` in
      #     app/components/tabler_ui/navbar/component.rb; see the spec file
      #     header for how that's checked).
      #   arg: [Symbol, nil] the name of the method's first required
      #     positional parameter -- e.g. :title for `tabs.tab("Title")`,
      #     :page for `pagination.item(1)`. nil when the method takes no
      #     required positional argument at all, e.g. a bare `dropdown.gap`
      #     or `navbar_group.divider`, where every input (if any) is
      #     optional and lives in the trailing options Hash. Per CLAUDE.md
      #     rule 4 this is always a `:req` parameter when present, never
      #     `:opt` -- these are the mandatory arguments the rule requires to
      #     be positional.
      #   block: [Symbol, nil] :children when the method accepts a block
      #     rendered as this item's own content (`tabs.tab("Title") { ...
      #     }`); :items when the method instead yields *another builder
      #     object* one level deeper (only `navbar`'s `left`/`right`, and
      #     `left`/`right`'s own `dropdown`); nil when the method takes no
      #     block at all (e.g. `breadcrumb.item`, `dropdown.divider`).
      #   nests: [Symbol] present only when block: :items -- the level_name
      #     (a key of this same component's own Hash) that the yielded
      #     object's methods are listed under. Absent otherwise.
      #
      # ## navbar's levels
      #
      # `:root` (Navbar::Component) has `left`/`right`, each yielding a
      # `NavigationGroup` -- `nests: :group`.
      #
      # `:group` (Navbar::Component::NavigationGroup, yielded by
      # `left`/`right`) has `add` (a plain link), `dropdown` (yields a
      # further nested `DropDownProxy` -- `nests: :dropdown`),
      # `dark_mode_toggle`, and `divider`.
      #
      # `:dropdown` (Navbar::Component::NavigationGroup::DropDownProxy,
      # yielded by `:group`'s `dropdown`) has `item`, `divider`, `header` --
      # deliberately the same builder vocabulary as the standalone
      # `TablerUi::Dropdown::Component` (see that class's own doc comment),
      # so this level's entries mirror `"dropdown" => { root: { ... } }`
      # below almost exactly.
      module BuilderMap
        BUILDERS = {
          "accordion" => {
            root: {
              "item" => { klass: "Component", arg: :title, block: :children }.freeze
            }.freeze
          }.freeze,

          "breadcrumb" => {
            root: {
              "item" => { klass: "Component", arg: :title, block: nil }.freeze
            }.freeze
          }.freeze,

          "carousel" => {
            root: {
              # No mandatory positional -- a slide's content comes entirely
              # from :image (in options) or the block; there is no single
              # obvious required string the way tabs/steps/breadcrumb have a
              # title. See Carousel::Component#item's own doc comment.
              "item" => { klass: "Component", arg: nil, block: :children }.freeze
            }.freeze
          }.freeze,

          "datagrid" => {
            root: {
              "item" => { klass: "Component", arg: :title, block: :children }.freeze
            }.freeze
          }.freeze,

          "dropdown" => {
            root: {
              "item" => { klass: "Component", arg: :title, block: nil }.freeze,
              "divider" => { klass: "Component", arg: nil, block: nil }.freeze,
              "header" => { klass: "Component", arg: :title, block: nil }.freeze
            }.freeze
          }.freeze,

          "navbar" => {
            root: {
              "left" => { klass: "Component", arg: nil, block: :items, nests: :group }.freeze,
              "right" => { klass: "Component", arg: nil, block: :items, nests: :group }.freeze
            }.freeze,
            group: {
              "add" => { klass: "Component::NavigationGroup", arg: :title, block: nil }.freeze,
              "dropdown" => {
                klass: "Component::NavigationGroup", arg: :title, block: :items, nests: :dropdown
              }.freeze,
              "dark_mode_toggle" => { klass: "Component::NavigationGroup", arg: nil, block: nil }.freeze,
              "divider" => { klass: "Component::NavigationGroup", arg: nil, block: nil }.freeze
            }.freeze,
            dropdown: {
              "item" => {
                klass: "Component::NavigationGroup::DropDownProxy", arg: :title, block: nil
              }.freeze,
              "divider" => {
                klass: "Component::NavigationGroup::DropDownProxy", arg: nil, block: nil
              }.freeze,
              "header" => {
                klass: "Component::NavigationGroup::DropDownProxy", arg: :title, block: nil
              }.freeze
            }.freeze
          }.freeze,

          "pagination" => {
            root: {
              "item" => { klass: "Component", arg: :page, block: nil }.freeze,
              # #gap takes no options Hash at all (`def gap`, no arguments) --
              # arg/block are both nil the same as any other no-input method,
              # this is just the one builder method in the whole map that
              # doesn't even offer an auth: hook.
              "gap" => { klass: "Component", arg: nil, block: nil }.freeze,
              "prev" => { klass: "Component", arg: nil, block: nil }.freeze,
              "next" => { klass: "Component", arg: nil, block: nil }.freeze
            }.freeze
          }.freeze,

          "settings_page" => {
            root: {
              "item" => { klass: "Component", arg: :title, block: :children }.freeze
            }.freeze
          }.freeze,

          "steps" => {
            root: {
              "item" => { klass: "Component", arg: :title, block: nil }.freeze
            }.freeze
          }.freeze,

          "tabs" => {
            root: {
              "tab" => { klass: "Component", arg: :title, block: :children }.freeze
            }.freeze
          }.freeze,

          "timeline" => {
            root: {
              # No mandatory positional -- an event's content comes entirely
              # from the block. See Timeline::Component#item's own doc
              # comment ("unlike, say, Breadcrumb#item(title) ...").
              "item" => { klass: "Component", arg: nil, block: :children }.freeze
            }.freeze
          }.freeze
        }.freeze

        module_function

        # @param component [String, Symbol] a component name (its directory
        #   name under app/components/tabler_ui, e.g. "navbar")
        # @return [Hash] that component's levels Hash (level_name => method
        #   name => descriptor), or {} for a component with no entry here --
        #   never nil, never raises, mirroring SlotMap.slots_for's contract
        #   so callers don't need to special-case a non-builder-style name.
        def levels_for(component)
          BUILDERS.fetch(component.to_s, {})
        end

        # @param component [String, Symbol] a component name
        # @param level [String, Symbol] a level name (default: :root, the
        #   one level every entry has; navbar additionally has :group and
        #   :dropdown -- see the module doc's "navbar's levels" section)
        # @return [Hash] method name => descriptor for that level, or {} if
        #   the component or level doesn't exist
        def methods_for(component, level = :root)
          levels_for(component).fetch(level.to_sym, {})
        end
      end
    end
  end
end
