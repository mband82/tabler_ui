# frozen_string_literal: true

require "tabler_ui/docs/navigation"
require "tabler_ui/docs/doc_parser"
require "tabler_ui/docs/demo_registry"
require "tabler_ui/docs/engine"

module TablerUi
  module Docs
    # Client-side full-text search index for the docs engine: one flat
    # array of small Hash entries built from the same three sources every
    # other docs page already reads from (Navigation, DocParser,
    # DemoRegistry) -- no separate content is authored for search, so it
    # can never drift from what the pages themselves show.
    #
    # Served as JSON by SearchController#index (GET /ui/search, see
    # docs/config/routes.rb) and filtered entirely client-side by the
    # tabler-ui--docs-search Stimulus controller -- see
    # docs/app/javascript/controllers/tabler_ui/docs/search_controller.js
    # for why (no server round-trip per keystroke).
    #
    # ## Entry shape
    #
    # Each entry is a Hash with symbol keys:
    #
    #   :kind      -- "component", "section", "option", "example" or "demo"
    #   :label     -- short display text (a component's title, a section's
    #                 heading, an option's ":name", an example's title, a
    #                 demo's title)
    #   :component -- owning component name (String), e.g. "table"
    #   :context   -- a short, whitespace-squished snippet for the result
    #                 line (a description, a section's body, an option's
    #                 type + description, an example's code, a demo's
    #                 source), truncated to CONTEXT_LENGTH chars
    #   :path      -- the real route to the page this entry lives on --
    #                 always the per-component doc page
    #                 (TablerUi::Docs::Engine's `component_path`, see
    #                 ComponentsController) today, generated through the
    #                 engine's own url_helpers rather than hand-built so it
    #                 stays correct however the host app mounts this engine
    #   :anchor    -- a URL fragment (no leading "#") to jump straight to
    #                 the right card, or nil when the entry has none.
    #                 Only "demo" entries carry one: `demo.slug`, which is
    #                 also the `id:` every demo card renders with (see
    #                 docs/app/views/tabler_ui/docs/demos/_demo.html.erb).
    #                 Component/section/option/example entries land on the
    #                 top of the component page with no anchor -- the
    #                 per-component page (docs/app/views/tabler_ui/docs/components/show.html.erb,
    #                 other agents' work) has no established per-section
    #                 anchor convention of its own yet.
    #
    # ## Caching
    #
    # .entries memoizes the built array in a module-level ivar, built once
    # per process on first call and never rebuilt after. This mirrors
    # DemoRegistry (registered once at gem-boot, never re-scanned) rather
    # than DocParser (which re-checks every component file's mtime on
    # every call): unlike DocParser, this module isn't on a per-request
    # hot path that benefits from picking up a same-process doc-comment
    # edit -- it exists to answer "what's in the index", and re-walking
    # DocParser.all (itself mtime-checked, so cheap once everything is
    # already parsed) plus DemoRegistry.all (a static, in-memory Array) on
    # every search request would be pure waste for content that only
    # changes when source code does.
    #
    # Like DocParser, DemoRegistry and Navigation, this file lives under
    # docs/lib -- on $LOAD_PATH (see the gemspec's require_paths) but NOT
    # Zeitwerk-autoloaded (see doc_parser.rb's own "Caching" section for
    # why) -- so in Rails development this module is never itself reloaded
    # between requests either. Editing search_index.rb needs a server
    # restart to take effect, same as editing navigation.rb or
    # demo_registry.rb does. #reset! exists only for specs that want a
    # clean slate.
    #
    # ## Payload size
    #
    # ~676 entries today (35 components + ~335 options + ~176 examples +
    # ~22 sections + 108 demos) serialize to roughly 170KB of
    # uncompressed JSON -- large enough to be worth a second look if this
    # ever needs to ship over a slow connection, though ordinary gzip
    # (most hosts already compress JSON responses) should take a real bite
    # out of that given how repetitive the option/example rows are.
    # SearchController#index does not attempt any deeper size reduction
    # (paging, a smaller field set, server-side matching) -- fetched once
    # per page load and cached at the module level in JS, this trades a
    # bit of one-time transfer for a search box with no further server
    # round-trips at all.
    module SearchIndex
      # Longest :context snippet returned, after whitespace-squishing --
      # long enough to give a reader a hint, short enough that 100+
      # entries of it don't bloat the JSON payload.
      CONTEXT_LENGTH = 160

      module_function

      # @return [Array<Hash>] every entry, memoized -- see the "Caching"
      #   section above.
      def entries
        @entries ||= build
      end

      # Drops the memoized array. Not needed for normal operation --
      # exists for specs that want a clean slate.
      def reset!
        @entries = nil
      end

      # Rebuilds the array from scratch, unmemoized. #entries is the
      # normal entry point; this is exposed separately so a spec can
      # compare two independent builds without reaching into the ivar.
      #
      # @return [Array<Hash>]
      def build
        component_entries + demo_entries
      end

      # @api private
      # @return [Array<Hash>] one "component" entry plus one "section",
      #   "option" and "example" entry per parsed doc-comment structure,
      #   for every component Navigation knows about.
      def component_entries
        Navigation.components.flat_map do |name|
          parsed = DocParser.find(name) || ParsedComponent.new(name)

          [description_entry(name, parsed)] +
            section_entries(name, parsed) +
            option_entries(name, parsed) +
            example_entries(name, parsed)
        end
      end

      # @api private
      def description_entry(name, parsed)
        build_entry(kind: "component", label: Navigation.title_for(name), component: name,
                     context: parsed.description, anchor: nil)
      end

      # @api private
      def section_entries(name, parsed)
        parsed.sections.map do |section|
          build_entry(kind: "section", label: section.title, component: name,
                       context: section.body, anchor: nil)
        end
      end

      # @api private
      def option_entries(name, parsed)
        parsed.options.map do |option|
          build_entry(kind: "option", label: ":#{option.name}", component: name,
                       context: "#{option.type} -- #{option.description}", anchor: nil)
        end
      end

      # @api private
      def example_entries(name, parsed)
        parsed.examples.map do |example|
          build_entry(kind: "example", label: example.title.presence || "Example", component: name,
                       context: example.code, anchor: nil)
        end
      end

      # @api private
      # @return [Array<Hash>] one "demo" entry per DemoRegistry.all, across
      #   every component -- not just the ones Navigation.components lists,
      #   so a component with demos but (hypothetically) no parseable doc
      #   comment still gets its demos indexed.
      def demo_entries
        DemoRegistry.all.map do |demo|
          build_entry(kind: "demo", label: demo.title, component: demo.component.to_s,
                       context: demo.source, anchor: demo.slug)
        end
      end

      # @api private
      def build_entry(kind:, label:, component:, context:, anchor:)
        {
          kind: kind,
          label: label.to_s,
          component: component.to_s,
          context: squish_truncate(context),
          path: route_helpers.component_path(component),
          anchor: anchor
        }
      end

      # @api private
      def squish_truncate(text)
        text.to_s.squish.truncate(CONTEXT_LENGTH)
      end

      # @api private
      # @return the isolated docs engine's own url_helpers -- generates
      #   `component_path` correctly prefixed with wherever the host app
      #   mounted TablerUi::Docs::Engine (a fixed, single mount point, the
      #   supported case -- see Rails::Engine's own routing guide), rather
      #   than this module hand-assuming a mount path like "/ui".
      def route_helpers
        Engine.routes.url_helpers
      end
    end
  end
end
