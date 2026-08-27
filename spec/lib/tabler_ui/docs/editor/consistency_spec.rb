# frozen_string_literal: true

require "rails_helper"
require "json"
require "tabler_ui/docs/editor/contract"
require "tabler_ui/docs/editor/renderer"
require "tabler_ui/docs/editor/erb_generator"
require "tabler_ui/docs/editor/enum_map"

# The consistency guard between the design editor's two tree-walkers:
# Renderer (tree -> preview HTML, via the real `tabler_ui.*` dispatcher) and
# ErbGenerator (tree -> exportable .html.erb source). If they ever disagree,
# the editor's live preview lies about what the exported code will produce --
# the worst failure mode this feature can have. One such drift already
# happened (ErbGenerator emitted an empty `do |slots| ... end` for a
# component with no slots/items, where Renderer correctly passed no block at
# all -- see erb_generator_spec.rb's own regression test for it) and neither
# module's own spec caught it; only an end-to-end run did. This file IS that
# end-to-end run, permanently, over a committed fixture corpus
# (spec/fixtures/editor/*.json) instead of an ad-hoc manual check.
#
# ## `render inline:` is legitimate HERE, and ONLY here
#
# Both Renderer's and ErbGenerator's own class docs carry an explicit warning
# against ever turning attacker-controlled tree data into an ERB string and
# `render inline:`-ing it -- that is RCE in every host app this engine
# mounts into (see docs/lib/tabler_ui/docs/parsed_component.rb and
# docs/app/views/tabler_ui/docs/components/show.html.erb for the same
# warning at the other two places user-shaped input meets a template
# renderer). The `render(inline:)` calls below do NOT violate that: every
# node they render comes from spec/fixtures/editor/*.json, which are
# gem-authored, committed, code-reviewed files -- not request input. This is
# exactly the curated-corpus side of the boundary demo_registry_spec.rb
# already draws for DemoRegistry (its own `render(inline: demo.source)`) and
# erb_generator_spec.rb draws for its own hand-written fixtures. This
# pattern must never move into application code, where turning a request
# body into ERB source and rendering it is exactly the RCE both classes'
# docs warn about.
#
# ## Why the fixtures are JSON but an enum-as-symbol value survives the trip
#
# Contract's node shape uses real Ruby Symbols for an option whose
# `EnumMap.symbol?(component, option)` is true (dropdown's `align:`, tabs'
# `style:`, ...) -- see tree.rb's own "matching EnumMap.symbol? are real
# Symbols, not Strings" note. JSON has no Symbol type, so every fixture
# necessarily stores such a value as the same bare String as an
# enum-as-STRING option would (`"align": "end"` looks identical to
# `"size": "lg"` on disk). #load_fixture below re-derives the Symbol the
# exact same way Tree does -- via EnumMap.symbol?(component, option), not by
# hardcoding which fixture uses which -- so what Renderer/ErbGenerator
# actually receive is a real Contract-shaped node, Symbol values included,
# not a JSON-flattened approximation of one. This is fixture-loading
# infrastructure only; it does not re-validate anything Tree already
# validates (empty by design -- see contract.rb and tree.rb, another
# agent's files, which this spec does not touch).
#
# Every fixture was authored as a Ruby Hash and confirmed to be a fixed
# point under `TablerUi::Docs::Editor::Tree.call` (`result.errors == []` and
# `result.node == the_hash_itself`) before being serialized to JSON --
# i.e. each one is already the shape Tree would have produced, not merely
# "close enough".
RSpec.describe "Renderer/ErbGenerator consistency" do
  Contract = TablerUi::Docs::Editor::Contract
  Renderer = TablerUi::Docs::Editor::Renderer
  ErbGenerator = TablerUi::Docs::Editor::ErbGenerator
  EnumMap = TablerUi::Docs::Editor::EnumMap

  FIXTURES_DIR = File.expand_path(File.join(__dir__, "..", "..", "..", "..", "fixtures", "editor"))
  FIXTURE_NAMES = Dir.glob(File.join(FIXTURES_DIR, "*.json")).map { |p| File.basename(p, ".json") }.sort

  # Global-state warning (TablerUi.auth_method, see lib/tabler_ui.rb and
  # erb_generator_spec.rb's own identical around block): a builder item with
  # no explicit `auth:` still goes through whatever auth_method is currently
  # configured, so an earlier spec elsewhere in the suite that left a custom
  # one installed would silently drop items here. Save/restore around every
  # example.
  around do |example|
    original = TablerUi.auth_method
    TablerUi.auth_method = ->(*) { true }
    example.run
    TablerUi.auth_method = original
  end

  # --- Fixture loading -------------------------------------------------

  # Mirrors Tree's own EnumMap-driven coercion (see this file's header) --
  # the one thing a JSON round trip cannot preserve on its own.
  def symbolize_enum_options!(node)
    return node unless node.is_a?(Hash)

    if node["kind"] == "component" && node["options"].is_a?(Hash)
      node["options"].each do |key, value|
        node["options"][key] = value.to_sym if value.is_a?(String) && EnumMap.symbol?(node["name"], key)
      end
    end

    node.each_value do |value|
      case value
      when Hash then symbolize_enum_options!(value)
      when Array then value.each { |v| symbolize_enum_options!(v) }
      end
    end

    node
  end

  def load_fixture(name)
    node = JSON.parse(File.read(File.join(FIXTURES_DIR, "#{name}.json")))
    symbolize_enum_options!(node)
  end

  # A fresh, real view context per render -- TablerUi::Helper mixed in, the
  # main engine's component view path only (no docs engine needed: nothing
  # here renders a docs partial). Mirrors erb_generator_spec.rb's
  # `plain_view_context` / demo_registry_spec.rb's `demo_view_context`,
  # trimmed to what this file needs. Fresh per call, not memoized, so
  # Renderer's render and the generated-ERB render never share state.
  def view_context
    view_paths = ActionView::PathSet.new([TablerUi::Engine.root.join("app/components").to_s])
    view_class = ActionView::Base.with_empty_template_cache
    view_class.include(TablerUi::Helper)
    view_class.with_view_paths(view_paths, {})
  end

  # --- Structural HTML comparison ---------------------------------------

  # Renderer stamps these; ErbGenerator (correctly) never does -- see both
  # classes' own doc comments. Stripped before comparison, not compared.
  EDITOR_ATTRS = %w[data-editor-node-id data-editor-field].freeze

  # Canonicalizes one HTML fragment into a plain nested Array/Hash structure
  # that is strict about element names, attribute values and text content,
  # but blind to whitespace-only text nodes and to Hash key (attribute)
  # order -- exactly "lenient about whitespace and attribute order, strict
  # about elements/classes/text".
  def canonicalize_node(node)
    case node
    when Nokogiri::XML::Element
      attrs = node.attributes.each_with_object({}) do |(name, attr), acc|
        acc[name] = attr.value unless EDITOR_ATTRS.include?(name)
      end
      { tag: node.name, attrs: attrs, children: node.children.filter_map { |c| canonicalize_node(c) } }
    when Nokogiri::XML::Text, Nokogiri::XML::CDATA
      text = node.text.gsub(/\s+/, " ").strip
      text.empty? ? nil : { text: text }
    end
    # Comments and other node types are dropped entirely -- neither Renderer
    # nor ErbGenerator ever emits an HTML comment.
  end

  def canonicalize(html)
    Nokogiri::HTML5.fragment(html.to_s).children.filter_map { |c| canonicalize_node(c) }
  end

  # --- (a) + (b) + (c): per-fixture consistency --------------------------

  describe "fixture corpus" do
    FIXTURE_NAMES.each do |name|
      context name do
        it "renders through Renderer and ErbGenerator without error, and the two agree" do
          node = load_fixture(name)

          renderer_html = nil
          expect { renderer_html = Renderer.new(view_context).render(node) }.not_to raise_error
          expect(renderer_html).to be_a(ActiveSupport::SafeBuffer)
          expect(renderer_html).not_to include("alert alert-danger"),
                                        "Renderer produced an error marker for a fixture meant to be valid:\n#{renderer_html}"

          generated = nil
          expect { generated = ErbGenerator.new(node).call }.not_to raise_error
          expect(generated).to be_a(String)

          # (c) contenteditable is a runtime-only, browser-applied attribute
          # -- see contract.rb's "deliberately absent" section. Neither
          # output may ever carry it.
          expect(renderer_html.downcase).not_to include("contenteditable")
          expect(generated.downcase).not_to include("contenteditable")

          # (b) The strongest check: actually render the generated ERB (see
          # this file's header for why `render inline:` is legitimate here)
          # and compare its real output against Renderer's, structurally.
          rendered_from_generated = view_context.render(inline: generated)

          expect(canonicalize(rendered_from_generated)).to eq(canonicalize(renderer_html)),
                                                             "Renderer and the rendered generated-ERB disagree for " \
                                                             "'#{name}'.\n\nRenderer:\n#{renderer_html}\n\n" \
                                                             "Generated ERB:\n#{generated}\n\nRendered generated ERB:\n#{rendered_from_generated}"
        end
      end
    end
  end

  # --- table's declarative :columns/:data -----------------------------

  # The fixture-corpus loop above already proves structural agreement for
  # table_declarative_columns (a table with no explicit fixture-specific
  # assertion could still "agree" while both sides silently rendered every
  # cell blank -- a String-vs-Symbol row-key mismatch would do exactly
  # that, agreeing on an empty <td></td> either way). This is the positive
  # check the task calls for: real header text and real cell values, on
  # both sides, not just "the two sides match whatever they produced".
  describe "table_declarative_columns" do
    it "renders real header text and cell values, matching on both the Renderer and generated-ERB sides" do
      node = load_fixture("table_declarative_columns")

      renderer_html = Renderer.new(view_context).render(node).to_s
      generated = ErbGenerator.new(node).call
      rendered_from_generated = view_context.render(inline: generated).to_s

      [renderer_html, rendered_from_generated].each do |html|
        expect(html).to include("Name", "Role", "Ada Lovelace", "Mathematician", "Grace Hopper", "Rear Admiral")
      end
    end
  end

  # --- (d) Structural guard: every Contract::KINDS entry is implemented in
  #     both modules ------------------------------------------------------

  # A minimal, individually-valid node for each of the 7 kinds that flow
  # through each module's own top-level `render_node` dispatch (its `case
  # node["kind"]`, in both Renderer and ErbGenerator -- confirmed by reading
  # both files: see renderer.rb#render_node and erb_generator.rb#render_node).
  # `builder_item` is deliberately excluded here -- see the dedicated
  # "builder_item" example below for why it is not part of that case at all,
  # in either module, by design.
  TOP_LEVEL_PROBE_NODES = {
    "fragment" => { "kind" => "fragment", "id" => "probe", "children" => [] },
    "row" => { "kind" => "row", "id" => "probe", "attrs" => {}, "children" => [] },
    "column" => { "kind" => "column", "id" => "probe", "span" => {}, "attrs" => {}, "children" => [] },
    "heading" => { "kind" => "heading", "id" => "probe", "level" => 1, "content" => "x" },
    "text" => { "kind" => "text", "id" => "probe", "tag" => "p", "content" => "x" },
    "component" => { "kind" => "component", "id" => "probe", "name" => "badge", "args" => {}, "options" => {},
                      "html" => {}, "slots" => {} },
    "partial" => { "kind" => "partial", "id" => "probe", "path" => "x.html.erb" }
  }.freeze

  describe "Contract::KINDS coverage (rule: a new kind must fail loudly until both modules implement it)" do
    it "lists every kind exactly once, matching what this spec covers" do
      expect(Contract::KINDS.sort).to eq((TOP_LEVEL_PROBE_NODES.keys + ["builder_item"]).sort)
    end

    TOP_LEVEL_PROBE_NODES.each do |kind, probe|
      it "Renderer's top-level dispatch has a real branch for '#{kind}' (not the 'unknown node kind' fallback)" do
        html = Renderer.new(view_context).send(:render_node, probe, 1).to_s

        expect(html).not_to include("unknown node kind")
      end

      it "ErbGenerator's top-level dispatch has a real branch for '#{kind}' (does not raise 'unknown node kind')" do
        expect { ErbGenerator.new(probe).send(:render_node, probe, 0, []) }
          .not_to raise_error
      end
    end

    it "an unrecognised kind DOES trip Renderer's fallback (sanity check on the probe method itself)" do
      html = Renderer.new(view_context).send(:render_node, { "kind" => "bogus", "id" => "x" }, 1).to_s
      expect(html).to include("unknown node kind")
    end

    it "an unrecognised kind DOES raise from ErbGenerator (sanity check on the probe method itself)" do
      bogus = { "kind" => "bogus", "id" => "x" }
      expect { ErbGenerator.new(bogus).send(:render_node, bogus, 0, []) }
        .to raise_error(ArgumentError, /unknown node kind/)
    end

    # `builder_item` is structurally different from the other 7 kinds: per
    # contract.rb, it is legal ONLY inside a component's (or another
    # builder_item's) `items` array -- Tree's own ROOT_KINDS/
    # NON_ROW_CONTAINER_KINDS/ROW_CONTAINER_KINDS never include it, only
    # `normalize_items`'s hardcoded `allowed_kinds: %w[builder_item]` does.
    # Correspondingly, NEITHER module ever routes a builder_item node
    # through its top-level `render_node` -- Renderer walks items via
    # #emit_items/#emit_item (keyed off `item["method"]` + BuilderMap, never
    # `item["kind"]`) and ErbGenerator walks them via
    # #render_builder_items/#render_builder_item (same). That asymmetry is
    # correct, not a gap -- this example proves coverage exists via the
    # pathway each module actually uses, the same way the corpus-level specs
    # above already exercise it end-to-end (navbar_three_level_chain,
    # dropdown_and_tabs, accordion_and_datagrid, ...).
    it "both modules implement 'builder_item' via their own items-array walker, not top-level dispatch" do
      tree = {
        "kind" => "component", "id" => "probe-root", "name" => "tabs", "args" => { "id" => "probe-tabs" },
        "options" => {}, "html" => {},
        "items" => [
          { "kind" => "builder_item", "id" => "probe-item", "method" => "tab", "args" => { "title" => "Probe" },
            "options" => {}, "html" => {}, "children" => [] }
        ]
      }

      renderer_html = Renderer.new(view_context).render(tree).to_s
      expect(renderer_html).not_to include("alert alert-danger")
      expect(renderer_html).to include("Probe")

      generated = ErbGenerator.new(tree).call
      expect(generated).to include('tabs.tab "Probe"')
    end
  end

  # --- (e) Decoration must stay off in this file ---------------------------
  #
  # This file's whole reason to exist is comparing Renderer's preview HTML
  # against the rendered generated ERB -- and Renderer's `decorate:` flag
  # (see its own "Decoration" class docs) adds design-editor-only guide
  # markup that ErbGenerator has, and must keep, no concept of at all (see
  # erb_generator_spec.rb's own "decoration-free output" coverage). If any
  # of this file's `Renderer.new(view_context)` calls ever started passing
  # `decorate: true`, every fixture comparison above would start failing for
  # the wrong reason -- not "the two walkers disagree" but "one of them
  # draws layout guides and the other doesn't" -- which would make this file
  # useless as the consistency guard it exists to be. A source-level check,
  # not a render-level one, on purpose: by the time a render-level
  # assertion could observe decoration leaking in here, every fixture
  # comparison above would already be red for a confusing reason instead of
  # this clear one.
  describe "decoration stays off in this file" do
    it "never constructs a Renderer with decorate: true" do
      # Matches a `decorate:` keyword argument inside a `Renderer.new(...)`
      # call specifically -- not a bare scan for the word "decorate" itself,
      # which this very example (and the surrounding comment) necessarily
      # contains and would otherwise always self-match.
      source = File.read(__FILE__)
      offending = source.scan(/Renderer\.new\([^)]*\)/).select { |call| call.include?("decorate:") }

      expect(offending).to be_empty,
        "this file must never enable Renderer decoration -- it exists to prove Renderer and ErbGenerator " \
        "agree on real markup, and decoration-only guide attributes are not real markup either walker's " \
        "output should be judged against. Offending call(s): #{offending.join(', ')}"
    end
  end
end
