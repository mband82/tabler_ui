# frozen_string_literal: true

module TablerUi
  module Docs
    # Navigation model for the docs engine's sidebar: every component the
    # gem ships, grouped into a handful of browsable sections.
    #
    # `components` is derived, not maintained. It walks
    # app/components/tabler_ui/*/component.rb -- the very same directories
    # TablerUi::Ui#method_missing resolves against by camelizing a method
    # name and constantizing it (see lib/tabler_ui/ui.rb). Nothing else in
    # the gem enumerates that list; this is the first place that does, so
    # it is the single source of truth for "what is a component" and
    # everything else here is checked against it.
    #
    # `CATEGORIES` is hand-maintained on purpose: a flat A-Z list of 35
    # names is worse for a reader than a handful of grouped sections, and
    # deciding which section a component belongs in is a judgment call a
    # directory listing can't make. It's modeled on the old dev showcase's
    # four pages (showcase/app/views/showcase/{layout,content,overlays}.html.erb
    # -- forms.html.erb demos TablerUi::FormBuilder, not components, so it
    # has no equivalent here; see the note on FORM_BUILDER below), extended
    # to cover the one component that showcase grouping silently missed
    # (dark_mode_toggle -- see UNDEMOED_BY_SHOWCASE).
    #
    # That showcase grouping had already rotted once before anyone noticed
    # (CLAUDE.md's "THE PROBLEM"). spec/lib/tabler_ui/docs/navigation_spec.rb
    # is the guard against CATEGORIES rotting the same way: every component
    # on disk must appear in it exactly once, and every name inside it must
    # be a real component directory. Keep that spec green rather than
    # patching around a failure -- a failure there means CATEGORIES is
    # wrong, not the spec.
    module Navigation
      # Root of the gem's app/components/tabler_ui tree, resolved the same
      # way app/components/tabler_ui/icon/component.rb finds its own gem
      # directory (File.expand_path against __dir__, not Rails.root --
      # this file has no guarantee an engine has finished booting when it
      # loads).
      COMPONENTS_ROOT = File.expand_path("../../../../app/components/tabler_ui", __dir__)

      # form_builder (lib/tabler_ui/form_builder.rb) deliberately has no
      # entry in `components` or `CATEGORIES`. It isn't a component
      # directory under app/components/tabler_ui -- it's an
      # ActionView::Helpers::FormBuilder subclass reached via
      # `tabler_form_with`/`tabler_ui_form_for`, not the `tabler_ui.*`
      # dispatcher -- so `components`, which is defined as "what the
      # directory walk finds," correctly does not produce it. Folding it
      # into CATEGORIES anyway would break the very guard this module
      # exists for: every name in CATEGORIES must resolve to a real
      # component directory, and form_builder has none. It gets its own
      # nav entry, outside this grouped-components model, when the sidebar
      # is wired up -- tracked here as a named constant so that decision
      # is visible rather than silently absent.
      FORM_BUILDER = "form_builder"

      # Ordered Hash: category display name => Array of component names
      # (Strings, matching the directory name under app/components/tabler_ui).
      # Order here is the sidebar's order, top to bottom -- a literal Hash
      # preserves insertion order in Ruby, so no separate ordering list is
      # needed.
      #
      # Hand-maintained; see the module doc above for why, and
      # navigation_spec.rb for the guard that keeps it honest against
      # `components`.
      CATEGORIES = {
        "Layout" => %w[
          accordion card card_group datagrid navbar page_header
          settings_page table tabs
        ],
        "Content" => %w[
          alert avatar badge badge_list breadcrumb button dark_mode_toggle
          dimmer empty icon illustration pagination placeholder progress
          rating ribbon spinner stat_card status steps timeline
        ],
        "Overlays" => %w[
          carousel dropdown modal offcanvas toast
        ]
      }.freeze

      # Components that render in the gem but had no demo of their own
      # anywhere in the old dev showcase -- not "used as a side effect of
      # demoing something else" (dark_mode_toggle IS rendered in
      # showcase/app/views/showcase/layout.html.erb, but only via
      # Navbar::Left#dark_mode_toggle, a builder method on navbar; nothing
      # in the showcase ever calls `tabler_ui.dark_mode_toggle` directly).
      # Recorded here so the content gap is visible rather than
      # rediscovered by hand later. Deliberately NOT asserted against in
      # navigation_spec.rb: a missing demo is a documentation gap to fill
      # in a later pass, not a structural break worth failing the suite
      # over the way a missing CATEGORIES entry is.
      UNDEMOED_BY_SHOWCASE = %w[dark_mode_toggle].freeze

      module_function

      # @return [Array<String>] every component name, derived by walking
      #   app/components/tabler_ui/*/component.rb. Sorted for a
      #   deterministic, diffable result -- Dir.glob's own order is
      #   filesystem-dependent.
      def components
        Dir.glob(File.join(COMPONENTS_ROOT, "*", "component.rb"))
           .map { |path| File.basename(File.dirname(path)) }
           .sort
      end

      # @return [Array<String>] category display names, in sidebar order.
      def category_names
        CATEGORIES.keys
      end

      # @param category [String] a key of CATEGORIES
      # @return [Array<String>] the component names in that category, in
      #   the order they render in the sidebar. Empty for an unknown
      #   category rather than raising -- callers rendering a sidebar
      #   shouldn't need to rescue a typo'd category name.
      def components_in(category)
        CATEGORIES.fetch(category, []).dup
      end

      # @param name [String, Symbol] a component name (its directory name
      #   under app/components/tabler_ui, e.g. "dark_mode_toggle")
      # @return [String, nil] the category it belongs to, or nil if none.
      #   nil is only reachable if CATEGORIES has rotted out of step with
      #   `components` -- navigation_spec.rb fails the suite before that
      #   can ship, so callers can treat a nil here as "can't happen"
      #   rather than a case they must handle.
      def category_for(name)
        name = name.to_s
        CATEGORIES.find { |_category, names| names.include?(name) }&.first
      end

      # @param name [String, Symbol] a component name, e.g. "dark_mode_toggle"
      # @return [String] a human display title, e.g. "Dark mode toggle".
      #   Rails' own String#humanize -- same convention the rest of the
      #   gem leaves to ActiveSupport rather than reimplementing.
      def title_for(name)
        name.to_s.humanize
      end
    end
  end
end
