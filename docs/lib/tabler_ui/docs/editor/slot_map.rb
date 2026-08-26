# frozen_string_literal: true

module TablerUi
  module Docs
    module Editor
      # Registry of which slot names each component's own template actually
      # reads, e.g. `slots.body` inside app/components/tabler_ui/card/_component.html.erb.
      #
      # This exists because TablerUi::SlotContext#method_missing
      # (lib/tabler_ui/ui.rb) accepts ANY name silently -- `slots.boyd` (a
      # typo of `body`) captures its block, stores it under a key nothing
      # ever reads, and renders nothing, with no error anywhere. There is no
      # other registry in the gem of "what are this component's real slot
      # names" -- a future design-editor property panel needs exactly that
      # list to offer slot buttons instead of guessing/misspelling, so this
      # module is that list.
      #
      # Hand-maintained, not derived at load time, for the same reason
      # docs/lib/tabler_ui/docs/navigation.rb's CATEGORIES is: docs/lib is on
      # $LOAD_PATH (gemspec require_paths) but is NOT Zeitwerk-autoloaded and
      # NOT reloaded in development, so a constant that re-globbed and
      # re-grepped app/components/tabler_ui/*/_component.html.erb on every
      # load would only ever reflect the state at server boot, and editing
      # this file already requires a server restart regardless -- deriving
      # it dynamically buys nothing at runtime, only cost. It's a plain
      # frozen constant module: no per-request mutable state.
      #
      # Derived once by hand via:
      #   grep -no 'slots\.[a-zA-Z_?!]*' app/components/tabler_ui/*/_component.html.erb
      # then excluding SlotContext's own real methods (`present?`, `empty?`)
      # from the matches -- those are calls on the SlotContext object itself,
      # not slot names. spec/lib/tabler_ui/docs/editor/slot_map_spec.rb
      # re-runs that same derivation at runtime and asserts equality against
      # SLOTS below -- keep that spec green rather than patching around a
      # failure; a failure there means SLOTS is wrong, not the spec.
      module SlotMap
        # Component name => Array of slot names its template reads via
        # `slots.<name>`. Only the 13 components below call `slots.*` for a
        # slot at all; the other 22 component templates take a plain block
        # (builder style) or no block, and deliberately have no key here --
        # see .slots_for for how callers should treat a missing key.
        #
        # Keys sorted alphabetically, and slot names within each array
        # sorted alphabetically, so this diffs deterministically regardless
        # of the order slots happen to appear in a template.
        SLOTS = {
          "alert" => %w[body].freeze,
          "avatar" => %w[overlay].freeze,
          "badge_list" => %w[body].freeze,
          "card" => %w[body footer header].freeze,
          "card_group" => %w[body].freeze,
          "dimmer" => %w[content].freeze,
          "empty" => %w[action header icon img].freeze,
          "modal" => %w[body footer header].freeze,
          "offcanvas" => %w[body footer header].freeze,
          "page_header" => %w[buttons].freeze,
          "ribbon" => %w[body].freeze,
          "table" => %w[filter footer].freeze,
          "toast" => %w[body header].freeze
        }.freeze

        module_function

        # @param component [String, Symbol] a component name (its directory
        #   name under app/components/tabler_ui, e.g. "card")
        # @return [Array<String>] the slot names its template reads, or an
        #   empty array for a component with no slots (or an unknown name)
        #   -- never nil, never raises, so callers don't need to special-case
        #   the 22 slot-less components.
        def slots_for(component)
          SLOTS.fetch(component.to_s, [])
        end
      end
    end
  end
end
