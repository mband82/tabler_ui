# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor/schema"
require "tabler_ui/docs/editor/contract"
require "tabler_ui/docs/editor/slot_map"
require "tabler_ui/docs/editor/builder_map"
require "tabler_ui/docs/navigation"
require "tabler_ui/docs/doc_parser"

# Schema assembles the design editor's whole palette/property-panel payload
# out of Contract, Navigation, DocParser and the three editor registries --
# this suite is less "does the math work" and more "does the assembly stay
# honest against the real sources it claims to describe", the same spirit
# as navigation_spec.rb/slot_map_spec.rb/builder_map_spec.rb/enum_map_spec.rb.
#
# TablerUi.auth_method (lib/tabler_ui.rb) is order-dependent global state
# other spec files mutate (see spec/support/shared_examples/auth_option.rb).
# Nothing in Schema reads it -- component classes are never instantiated
# here, only introspected (DocParser is pure text parsing, #args_for reads
# `instance_method(:initialize).parameters` without calling it) -- but
# Schema DOES memoize its own payload in a module ivar, so the `around`
# block below still saves/restores auth_method (cheap insurance against a
# future Schema change that reads it) and always resets the memoized
# payload before and after every example, so no example's build can leak
# into another's regardless of --seed.
RSpec.describe TablerUi::Docs::Editor::Schema do
  Contract = TablerUi::Docs::Editor::Contract
  Navigation = TablerUi::Docs::Navigation
  DocParser = TablerUi::Docs::DocParser

  # component name => its one mandatory positional's parameter name. The
  # only 8 of the 35 components whose `initialize` takes one at all -- see
  # CLAUDE.md's architecture brief and Contract's own node-kind doc.
  REQUIRED_POSITIONAL = {
    "accordion" => "id", "carousel" => "id", "modal" => "id", "offcanvas" => "id",
    "settings_page" => "id", "tabs" => "id", "icon" => "icon", "illustration" => "name"
  }.freeze

  around do |example|
    original_auth_method = TablerUi.auth_method
    described_class.reset!
    example.run
  ensure
    described_class.reset!
    TablerUi.auth_method = original_auth_method
  end

  let(:payload) { described_class.as_json }

  describe ".as_json / .build / .reset!" do
    it "memoizes -- the same object comes back on repeated calls" do
      expect(described_class.as_json).to equal(described_class.as_json)
    end

    it "#reset! clears the memo -- the next #as_json call rebuilds" do
      first = described_class.as_json
      described_class.reset!
      second = described_class.as_json

      expect(first).to eq(second)
      expect(first).not_to equal(second)
    end

    it "#build never memoizes, unlike #as_json" do
      expect(described_class.build).not_to equal(described_class.build)
    end
  end

  describe "top-level shape" do
    it "carries exactly version, limits, layout, kinds, categories, components" do
      expect(payload.keys).to match_array(%w[version limits layout kinds categories components])
    end

    it "version matches Contract::VERSION" do
      expect(payload["version"]).to eq(Contract::VERSION)
    end

    it "limits matches Contract::LIMITS, string-keyed, unchanged values" do
      expect(payload["limits"]).to eq(Contract::LIMITS.transform_keys(&:to_s))
    end

    it "layout is row/column/heading/text/partial -- Contract::KINDS minus fragment/component/builder_item" do
      expect(payload["layout"]).to eq(%w[row column heading text partial].map { |k| { "kind" => k } })
      expect(described_class::LAYOUT_KINDS).to eq(Contract::KINDS - %w[fragment component builder_item])
    end
  end

  # The editor's property panel builds the non-component kinds' controls from
  # this section. Before it existed, inspector.js carried a hand-typed copy of
  # each of these lists, which would have rotted silently the first time
  # Contract gained a text tag or Breakpoint gained a size. Publishing them and
  # asserting equality here is what makes the client's copy unnecessary.
  describe "kinds -- the vocabularies only Contract knows" do
    it "publishes heading levels, text tags, span keys/values and attribute keys, straight from Contract" do
      kinds = payload["kinds"]

      expect(kinds["heading"]["levels"]).to eq(Contract::HEADING_LEVELS.to_a)
      expect(kinds["text"]["tags"]).to eq(Contract::TEXT_TAGS)
      expect(kinds["column"]["spanKeys"]).to eq(Contract::SPAN_KEYS)
      expect(kinds["column"]["spanValues"]).to eq(Contract::SPAN_VALUES)
      expect(kinds["attrs"]["keys"]).to eq(Contract::ATTR_KEYS)
      expect(kinds["attrs"]["nestedKeys"]).to eq(Contract::ATTR_NESTED_KEYS)
    end

    it "carries every breakpoint a column can span at, so the panel offers all of them" do
      expect(payload["kinds"]["column"]["spanKeys"]).to include(*TablerUi::Breakpoint::ALL)
    end

    it "serializes to JSON without losing anything -- it crosses the wire as the schema endpoint's body" do
      round_tripped = JSON.parse(JSON.generate(payload))["kinds"]

      expect(round_tripped).to eq(payload["kinds"])
    end
  end

  describe "categories" do
    it "matches Navigation's category_names/components_in exactly, in order" do
      expected = Navigation.category_names.map do |label|
        { "label" => label, "components" => Navigation.components_in(label) }
      end

      expect(payload["categories"]).to eq(expected)
    end
  end

  describe "components" do
    it "has all 35 Navigation components, no more, no fewer" do
      expect(payload["components"].keys.sort).to eq(Navigation.components.sort)
      expect(payload["components"].size).to eq(35)
    end

    it "every entry carries exactly the documented key set" do
      payload["components"].each_value do |entry|
        expect(entry.keys).to match_array(
          %w[title description docPath args options htmlParts slots builder unsupported]
        )
      end
    end

    it "title is Navigation.title_for" do
      expect(payload["components"]["dark_mode_toggle"]["title"]).to eq("Dark mode toggle")
    end
  end

  describe "args -- required positionals" do
    it "matches runtime introspection for all 8 components with a mandatory positional" do
      REQUIRED_POSITIONAL.each do |component, param_name|
        klass = "TablerUi::#{component.camelize}::Component".constantize
        actual = klass.instance_method(:initialize).parameters.select { |type, _| type == :req }.map { |_, n| n.to_s }

        expect(actual).to eq([param_name]) # sanity: still exactly one :req param, still this name
        expect(payload["components"][component]["args"]).to eq(
          [{ "name" => param_name, "control" => "text", "required" => true }]
        )
      end
    end

    it "every other component has an empty args list" do
      (Navigation.components - REQUIRED_POSITIONAL.keys).each do |component|
        expect(payload["components"][component]["args"]).to eq([]),
                                                                "expected #{component.inspect} to have no args"
      end
    end
  end

  describe "htmlParts" do
    it "card is root/header/body/footer/status, in doc-comment declaration order" do
      expect(payload["components"]["card"]["htmlParts"]).to eq(%w[root header body footer status])
    end

    it "maps bare :html -> root and :<part>_html -> <part> for every component, matching DocParser directly" do
      Navigation.components.each do |name|
        parsed = DocParser.find(name)
        expected = parsed.options.filter_map do |opt|
          next "root" if opt.name == "html"
          next opt.name.delete_suffix("_html") if opt.name.end_with?("_html")
        end.uniq

        expect(payload["components"][name]["htmlParts"]).to eq(expected), "component #{name.inspect}"
      end
    end
  end

  describe "slots" do
    it "matches SlotMap.slots_for exactly, for every component" do
      Navigation.components.each do |name|
        expect(payload["components"][name]["slots"]).to eq(TablerUi::Docs::Editor::SlotMap.slots_for(name))
      end
    end
  end

  describe "enum options" do
    it "dropdown's direction is select, with DIRECTIONS' keys and symbol: false" do
      option = payload["components"]["dropdown"]["options"].find { |o| o["name"] == "direction" }

      expect(option["control"]).to eq("select")
      expect(option["values"]).to eq(TablerUi::Dropdown::Component::DIRECTIONS.keys.map(&:to_s))
      expect(option["symbol"]).to be(false)
    end

    it "dropdown's align is select via the GLOBAL entry, with symbol: true" do
      option = payload["components"]["dropdown"]["options"].find { |o| o["name"] == "align" }

      expect(option["control"]).to eq("select")
      expect(option["values"]).to eq(%w[start end])
      expect(option["symbol"]).to be(true)
    end

    it "every select-control option (top-level or builder) carries a non-empty values array and a boolean symbol" do
      all_option_lists(payload).each do |options|
        options.select { |o| o["control"] == "select" }.each do |o|
          expect(o["values"]).to be_an(Array)
          expect(o["values"]).not_to be_empty
          expect([true, false]).to include(o["symbol"])
        end
      end
    end

    it "no non-select option carries a values or symbol key at all" do
      all_option_lists(payload).each do |options|
        options.reject { |o| o["control"] == "select" }.each do |o|
          expect(o).not_to have_key("values")
          expect(o).not_to have_key("symbol")
        end
      end
    end
  end

  describe "callables land in unsupported, never in options" do
    it "table's sort_url (#call)" do
      expect(payload["components"]["table"]["options"].map { |o| o["name"] }).not_to include("sort_url")
      expect(payload["components"]["table"]["unsupported"]).to include(
        { "name" => "sort_url", "type" => "#call", "reason" => "callable" }
      )
    end

    it "pagination's url (#call)" do
      expect(payload["components"]["pagination"]["options"].map { |o| o["name"] }).not_to include("url")
      expect(payload["components"]["pagination"]["unsupported"]).to include(
        { "name" => "url", "type" => "#call", "reason" => "callable" }
      )
    end

    it "rating's value (Object, not callable) still lands in unsupported with the Object reason" do
      expect(payload["components"]["rating"]["options"].map { |o| o["name"] }).not_to include("value")
      expect(payload["components"]["rating"]["unsupported"]).to include(
        { "name" => "value", "type" => "Object", "reason" => "opaque (Object)" }
      )
    end
  end

  describe "table's :columns/:data get a dedicated declarative control, not the generic 'json' escape hatch" do
    it "table's columns is control: 'columns', with a fields: describing the declarative shape" do
      option = payload["components"]["table"]["options"].find { |o| o["name"] == "columns" }

      expect(option["control"]).to eq("columns")
      expect(option["type"]).to eq("Array<Hash>") # unchanged -- only the derived control differs
      expect(option["fields"]).to eq(described_class::COLUMN_FIELDS)
      expect(option["fields"].find { |f| f["name"] == "key" }["required"]).to be(true)
    end

    it "table's data is control: 'rows', and carries no fields: (rows: shape follows columns:, not fixed)" do
      option = payload["components"]["table"]["options"].find { |o| o["name"] == "data" }

      expect(option["control"]).to eq("rows")
      expect(option["type"]).to eq("Enumerable")
      expect(option).not_to have_key("fields")
    end

    it "neither table option lands in unsupported any more" do
      names = payload["components"]["table"]["unsupported"].map { |u| u["name"] }

      expect(names).not_to include("columns", "data")
    end

    it "does NOT override datagrid's :items or rating's :choices -- both share :columns' own Array<Hash> " \
       "type string but stay on the generic 'json' control" do
      expect(payload["components"]["datagrid"]["options"].find { |o| o["name"] == "items" }["control"]).to eq("json")
      expect(payload["components"]["rating"]["options"].find { |o| o["name"] == "choices" }["control"]).to eq("json")
    end

    it "no non-'columns' option anywhere carries a fields: key" do
      all_option_lists(payload).each do |options|
        options.reject { |o| o["control"] == "columns" }.each do |o|
          expect(o).not_to have_key("fields")
        end
      end
    end
  end

  describe "auth is stripped everywhere" do
    it "the literal string 'auth' appears nowhere as a name in the serialized payload" do
      names = payload["components"].values.flat_map do |entry|
        entry["args"].map { |a| a["name"] } +
          entry["options"].map { |o| o["name"] } +
          entry["unsupported"].map { |u| u["name"] } +
          builder_method_names(entry["builder"])
      end

      expect(names).not_to include("auth")
    end

    it "sweeps the whole serialized JSON for a bare \"auth\" key or value, as a blunt backstop" do
      json = payload.to_json

      expect(json).not_to match(/"auth"/)
    end
  end

  describe "type vocabulary anti-rot" do
    it "every distinct type string across DocParser.all resolves through control_for without raising" do
      types = DocParser.all.flat_map { |_name, parsed| parsed.options.map(&:type) }.uniq

      expect(types.size).to be > 1 # sanity: DocParser actually found real options

      types.each do |type|
        expect { described_class.control_for(type) }.not_to raise_error,
                                                              "#{type.inspect} has no known control mapping -- " \
                                                              "extend Schema.control_for / STRUCTURED_TYPE_SETS"
      end
    end

    it "raises UnknownTypeError for a type string that matches none of the rules (regression guard)" do
      expect { described_class.control_for("SomeBrandNewFutureType") }
        .to raise_error(described_class::UnknownTypeError, /SomeBrandNewFutureType/)
    end

    it "does not silently swallow an unmapped structured type via an open-ended fallback (regression guard)" do
      expect { described_class.control_for("Array<Symbol>") }.to raise_error(described_class::UnknownTypeError)
    end
  end

  describe "docPath" do
    it "is generated through Engine's own route helpers, not hand-built" do
      Navigation.components.each do |name|
        expect(payload["components"][name]["docPath"])
          .to eq(TablerUi::Docs::Engine.routes.url_helpers.component_path(name))
      end
    end

    it "starts with the engine's mount prefix (/ui in this suite's dummy app)" do
      payload["components"].each_value do |entry|
        expect(entry["docPath"]).to start_with("/ui")
      end
    end
  end

  describe "builder" do
    it "is nil for every non-builder-style component" do
      (Navigation.components - TablerUi::Docs::Editor::BuilderMap::BUILDERS.keys).each do |name|
        expect(payload["components"][name]["builder"]).to be_nil
      end
    end

    it "covers exactly BuilderMap's components, with the same level names" do
      TablerUi::Docs::Editor::BuilderMap::BUILDERS.each do |component, levels|
        expect(payload["components"][component]["builder"].keys.sort).to eq(levels.keys.map(&:to_s).sort)
      end
    end

    it "bridges navbar dropdown/item's compound klass: to builder_options' bare DropDownProxy key" do
      item = payload["components"]["navbar"]["builder"]["dropdown"]["item"]

      expect(item["arg"]).to eq({ "name" => "title", "control" => "text", "required" => true })
      expect(item["options"].map { |o| o["name"] }).to include("url", "target", "icon")
    end

    it "a builder method with no mandatory positional carries arg: nil" do
      gap = payload["components"]["pagination"]["builder"]["root"]["gap"]

      expect(gap["arg"]).to be_nil
    end

    it "a builder method that nests into another level carries nests:" do
      left = payload["components"]["navbar"]["builder"]["root"]["left"]

      expect(left["nests"]).to eq("group")
      expect(left["block"]).to eq("items")
    end

    it "a builder method's own _html option lands in its htmlParts, not its options" do
      add = payload["components"]["navbar"]["builder"]["group"]["add"]

      expect(add["htmlParts"]).to include("link")
      expect(add["options"].map { |o| o["name"] }).not_to include("link_html")
    end
  end

  # @return [Array<Array<Hash>>] every options array in the payload -- every
  #   component's own top-level options, plus every builder method's
  #   options at every level.
  def all_option_lists(payload)
    payload["components"].values.flat_map do |entry|
      lists = [entry["options"]]
      next lists unless entry["builder"]

      entry["builder"].each_value do |methods|
        methods.each_value { |method_payload| lists << method_payload["options"] }
      end
      lists
    end
  end

  # @return [Array<String>] every builder method's own option/arg names, for
  #   the "auth is stripped everywhere" sweep above.
  def builder_method_names(builder)
    return [] unless builder

    builder.values.flat_map do |methods|
      methods.values.flat_map do |method_payload|
        names = method_payload["options"].map { |o| o["name"] } + method_payload["unsupported"].map { |u| u["name"] }
        names << method_payload["arg"]["name"] if method_payload["arg"]
        names
      end
    end
  end
end
