# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor/enum_map"
require "tabler_ui/docs/doc_parser"

# The point of this spec, like navigation_spec.rb's for CATEGORIES and
# slot_map_spec.rb's for SLOTS, is to keep a hand-maintained constant honest
# against the real source it claims to describe -- here, that means proving
# every PER_COMPONENT (component, option) pair names a real, currently
# documented option (assertion 2, cross-checked against DocParser), and that
# every value EnumMap lists for an option actually survives whatever runtime
# validation that option really has, where it has any at all (assertion 3).
# GLOBAL/PER_COMPONENT are lambda-based specifically so they can't silently
# drift from the real constants they reference (see enum_map.rb's own "Why
# the values are lambdas" note) -- this spec is the other half of that
# guarantee, catching drift in the *name*/*existence* axis a lambda alone
# can't.
RSpec.describe TablerUi::Docs::Editor::EnumMap do
  # Module-level validate! for every GLOBAL option name, called the same way
  # the real components that use them do.
  GLOBAL_VALIDATORS = {
    "color" => ->(value) { TablerUi::Color.validate!(value, context: "enum_map_spec") },
    "align" => ->(value) { TablerUi::Align.validate!(value, context: "enum_map_spec") },
    "position" => ->(value) { TablerUi::Position.validate!(value, context: "enum_map_spec") },
    "breakpoint" => ->(value) { TablerUi::Breakpoint.validate!(value, context: "enum_map_spec") }
  }.freeze

  # For every PER_COMPONENT (component, option) pair: either a lambda that
  # instantiates the real component with that option set (the same
  # ArgumentError path a caller would hit), or the Symbol :no_validate for a
  # confirmed-real option that has NO runtime raise-validation at all --
  # see enum_map.rb's "Only real, verified links" note for exactly why each
  # of those four has none (badge's size silently no-ops instead of
  # raising; illustration's size falls back to .to_i; placeholder's ratio/
  # type/animation are read with no validation whatsoever). Every mandatory
  # positional argument a component needs (id/name) is a fixed dummy value
  # -- only the option under test varies.
  PER_COMPONENT_VALIDATORS = {
    %w[button color] => ->(value) { TablerUi::Button::Component.new(color: value) },
    %w[button animate_icon] => ->(value) { TablerUi::Button::Component.new(animate_icon: value) },
    %w[alert color] => ->(value) { TablerUi::Alert::Component.new(color: value) },
    %w[alert link_style] => ->(value) { TablerUi::Alert::Component.new(link_style: value) },
    %w[card status_position] => ->(value) { TablerUi::Card::Component.new(status_position: value) },
    %w[badge size] => :no_validate,
    %w[placeholder size] => ->(value) { TablerUi::Placeholder::Component.new(type: :text, size: value) },
    %w[placeholder ratio] => :no_validate,
    %w[placeholder type] => :no_validate,
    %w[placeholder animation] => :no_validate,
    %w[page_header title_size] => ->(value) { TablerUi::PageHeader::Component.new(title_size: value) },
    %w[toast position] => ->(value) { TablerUi::Toast::Component.new(position: value) },
    %w[dropdown direction] => ->(value) { TablerUi::Dropdown::Component.new(direction: value) },
    %w[ribbon position] => ->(value) { TablerUi::Ribbon::Component.new(position: value) },
    %w[illustration size] => :no_validate,
    %w[modal size] => ->(value) { TablerUi::Modal::Component.new("enum-map-spec-modal", size: value) },
    %w[steps color] => ->(value) { TablerUi::Steps::Component.new(color: value) },
    %w[breadcrumb style] => ->(value) { TablerUi::Breadcrumb::Component.new(style: value) },
    %w[spinner type] => ->(value) { TablerUi::Spinner::Component.new(type: value) },
    %w[tabs style] => ->(value) { TablerUi::Tabs::Component.new("enum-map-spec-tabs", style: value) },
    %w[pagination size] => ->(value) { TablerUi::Pagination::Component.new(size: value) },
    %w[carousel indicators] => lambda { |value|
      TablerUi::Carousel::Component.new("enum-map-spec-carousel", indicators: value)
    }
  }.freeze

  # Resolves an entry's lambda to a plain Array<String> -- the same
  # stringification #values_for does, reimplemented here (rather than
  # calling #values_for itself) so this helper works for GLOBAL entries too,
  # which have no single "component" to pass #values_for.
  def resolve(entry)
    entry[:values].call.map(&:to_s)
  end

  # Every (component, option) pair PER_COMPONENT actually declares, paired
  # with its entry -- used to drive assertions 2 and 3 without listing the
  # 17 components by hand a second time.
  def each_per_component_entry
    described_class::PER_COMPONENT.each do |component, options|
      options.each do |option, entry|
        yield component, option, entry
      end
    end
  end

  describe "every resolver" do
    it "returns a non-empty Array of Strings for every GLOBAL entry" do
      described_class::GLOBAL.each do |option, entry|
        values = resolve(entry)

        expect(values).to be_an(Array), "GLOBAL[#{option.inspect}] did not resolve to an Array"
        expect(values).not_to be_empty, "GLOBAL[#{option.inspect}] resolved to an empty Array"
        expect(values.all? { |v| v.is_a?(String) }).to be(true),
                                                         "GLOBAL[#{option.inspect}] contains a non-String: #{values.inspect}"
      end
    end

    it "returns a non-empty Array of Strings for every PER_COMPONENT entry" do
      each_per_component_entry do |component, option, entry|
        values = resolve(entry)

        expect(values).to be_an(Array), "PER_COMPONENT[#{component.inspect}][#{option.inspect}] did not resolve to an Array"
        expect(values).not_to be_empty, "PER_COMPONENT[#{component.inspect}][#{option.inspect}] resolved to an empty Array"
        expect(values.all? { |v| v.is_a?(String) }).to be(true),
                                                         "PER_COMPONENT[#{component.inspect}][#{option.inspect}] contains a non-String: #{values.inspect}"
      end
    end
  end

  describe "every PER_COMPONENT option really exists" do
    # DocParser only recovers component-level @option rows (the block above
    # `def initialize`) -- builder sub-method options (a dropdown item's own
    # :url/:method/..., a tabs #tab's own :icon/:badge/...) are a different
    # agent's parallel task (see DocParser#builder_options) and are
    # deliberately out of scope here. Nothing in PER_COMPONENT above is a
    # sub-method option, so no filtering is needed -- this asserts the full
    # set.
    it "names an option DocParser recovers from the component's own initialize doc block" do
      each_per_component_entry do |component, option, _entry|
        parsed = TablerUi::Docs::DocParser.find(component)

        expect(parsed).not_to be_nil, "#{component.inspect} has no component.rb DocParser could find"

        option_names = parsed.options.map(&:name)
        expect(option_names).to include(option),
                                 "PER_COMPONENT[#{component.inspect}] lists #{option.inspect}, but DocParser found " \
                                 "no matching @option on #{component.inspect} -- found: #{option_names.inspect}"
      end
    end

    it "fires when an option name doesn't actually exist on the component (regression guard)" do
      # Proves the assertion above actually catches drift rather than
      # vacuously passing. Mutates a duplicate, not the frozen constant.
      broken = described_class::PER_COMPONENT.transform_values(&:dup)
      broken["button"]["not_a_real_option"] = { values: -> { %w[x] }, symbol: false }

      parsed = TablerUi::Docs::DocParser.find("button")
      option_names = parsed.options.map(&:name)

      expect(option_names).not_to include("not_a_real_option")
      expect(broken["button"]).to have_key("not_a_real_option")
    end
  end

  describe "every listed value survives its own runtime validation, where one exists" do
    it "every GLOBAL value survives the shared vocabulary module's own validate!" do
      described_class::GLOBAL.each do |option, entry|
        validator = GLOBAL_VALIDATORS.fetch(option) do
          raise "no validator registered in this spec for GLOBAL[#{option.inspect}] -- add one to GLOBAL_VALIDATORS"
        end

        resolve(entry).each do |string_value|
          value = entry[:symbol] ? string_value.to_sym : string_value

          expect { validator.call(value) }.not_to raise_error,
                                                    "GLOBAL[#{option.inspect}]'s value #{value.inspect} was rejected " \
                                                    "by its own validate!"
        end
      end
    end

    it "every PER_COMPONENT value survives the component's own validation, or is documented as unvalidated" do
      each_per_component_entry do |component, option, entry|
        validator = PER_COMPONENT_VALIDATORS.fetch([component, option]) do
          raise "no validator registered in this spec for PER_COMPONENT[#{component.inspect}][#{option.inspect}] -- " \
                "add one to PER_COMPONENT_VALIDATORS (a lambda, or :no_validate if genuinely unvalidated)"
        end

        next if validator == :no_validate

        resolve(entry).each do |string_value|
          value = entry[:symbol] ? string_value.to_sym : string_value

          expect { validator.call(value) }.not_to raise_error,
                                                    "PER_COMPONENT[#{component.inspect}][#{option.inspect}]'s value " \
                                                    "#{value.inspect} was rejected by #{component}'s own validation"
        end
      end
    end

    it "documents exactly which PER_COMPONENT entries have no runtime validate! to check" do
      unvalidated = PER_COMPONENT_VALIDATORS.select { |_key, validator| validator == :no_validate }.keys

      expect(unvalidated.sort).to eq(
        [%w[badge size], %w[illustration size], %w[placeholder animation], %w[placeholder ratio],
         %w[placeholder type]].sort
      )
    end

    it "fires when a bad value is injected for an option that IS raise-validated (regression guard)" do
      # Proves the assertion above actually catches drift rather than
      # vacuously passing. Mutates a duplicate, not the frozen constant --
      # button's color: is raise-validated (extra: BRAND + MUTED), so an
      # unknown color must raise.
      broken_entry = { values: -> { TablerUi::Color::ALL + ["not-a-real-color"] }, symbol: false }

      expect do
        TablerUi::Button::Component.new(color: resolve(broken_entry).last)
      end.to raise_error(ArgumentError, /unknown color/)
    end
  end

  describe "PER_COMPONENT overrides GLOBAL, rather than merging with it" do
    it "button's color: (extra BRAND + MUTED) is a superset of GLOBAL's plain color list" do
      global_colors = described_class.values_for("some-component-with-no-override", "color")
      button_colors = described_class.values_for("button", "color")

      expect(button_colors).to include(*global_colors)
      expect(button_colors.size).to be > global_colors.size
      expect(button_colors).to include("github", "muted")
    end

    it "ribbon's position: (VERTICAL only) is a strict subset of GLOBAL's position list" do
      global_positions = described_class.values_for("some-component-with-no-override", "position")
      ribbon_positions = described_class.values_for("ribbon", "position")

      expect(ribbon_positions).to eq(%w[top bottom])
      expect(global_positions).to include(*ribbon_positions)
      expect(ribbon_positions.size).to be < global_positions.size
    end
  end

  describe ".values_for" do
    it "resolves a GLOBAL entry for a component with no override" do
      expect(described_class.values_for("badge", "color")).to eq(TablerUi::Color::ALL)
    end

    it "resolves a PER_COMPONENT override in preference to GLOBAL" do
      expect(described_class.values_for("dropdown", "direction")).to eq(TablerUi::Dropdown::Component::DIRECTIONS.keys)
    end

    it "returns nil for an option name with no GLOBAL entry and no PER_COMPONENT override" do
      expect(described_class.values_for("badge", "not_a_real_option")).to be_nil
      expect(described_class.values_for("not_a_real_component", "not_a_real_option")).to be_nil
    end

    it "still resolves a GLOBAL option name for an unrecognised component -- GLOBAL is keyed by option name alone" do
      expect(described_class.values_for("not_a_real_component", "color")).to eq(TablerUi::Color::ALL)
    end

    it "accepts Symbols as well as Strings for both arguments" do
      expect(described_class.values_for(:badge, :color)).to eq(described_class.values_for("badge", "color"))
    end

    it "always returns Strings, even for a Symbol-backed option" do
      expect(described_class.values_for("dropdown", "align")).to eq(%w[start end])
    end
  end

  describe ".symbol?" do
    it "is true for an option the component reads back as a Symbol" do
      expect(described_class.symbol?("dropdown", "align")).to be(true)
    end

    it "is false for an option the component reads back as a String" do
      expect(described_class.symbol?("badge", "color")).to be(false)
    end

    it "is nil for a component/option pair with no entry in either Hash" do
      expect(described_class.symbol?("not_a_real_component", "not_a_real_option")).to be_nil
    end
  end

  describe "GLOBAL and PER_COMPONENT" do
    it "are frozen" do
      expect(described_class::GLOBAL).to be_frozen
      expect(described_class::PER_COMPONENT).to be_frozen
    end

    it "PER_COMPONENT's inner option Hashes are frozen too" do
      described_class::PER_COMPONENT.each_value do |options|
        expect(options).to be_frozen
      end
    end
  end
end
