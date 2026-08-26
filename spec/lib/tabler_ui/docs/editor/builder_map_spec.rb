# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor/builder_map"
require "tabler_ui/docs/navigation"

# The point of this spec is the same kind of guard navigation_spec.rb runs
# for CATEGORIES and editor/slot_map_spec.rb runs for SLOTS: BuilderMap::
# BUILDERS is hand-maintained (see the module doc for why -- docs/lib is not
# autoloaded or reloaded, so deriving it at load time would only ever
# reflect server-boot state anyway), so this spec re-derives the checkable
# parts of the truth fresh, at runtime, via reflection against the real
# component classes, and asserts BUILDERS against it. A wrong method name, a
# wrong `arg:`, a 12th component adopting `builder_style!` and not being
# added here, or navbar's nested levels drifting from the real
# NavigationGroup/DropDownProxy classes must all fail this spec, not go
# unnoticed.
RSpec.describe TablerUi::Docs::Editor::BuilderMap do
  # Walks a BUILDERS-shaped Hash and yields every (component, level,
  # method_name, descriptor) tuple, regardless of how many levels a
  # component has -- this is the generic walk the module doc says the shape
  # enables: no navbar-specific branching anywhere below. Defaults to the
  # real constant; the regression-guard examples pass a small broken Hash of
  # the same shape instead.
  def each_descriptor(builders = described_class::BUILDERS)
    return to_enum(:each_descriptor, builders) unless block_given?

    builders.each do |component, levels|
      levels.each do |_level, methods|
        methods.each do |method_name, descriptor|
          yield component, method_name, descriptor
        end
      end
    end
  end

  # @return [Class] the class a descriptor's `klass:` names, e.g.
  #   "TablerUi::Navbar::Component::NavigationGroup" for component "navbar",
  #   descriptor klass: "Component::NavigationGroup"
  def klass_for(component, descriptor)
    "TablerUi::#{component.camelize}::#{descriptor[:klass]}".constantize
  end

  # @return [Symbol, nil] the name of +method_name+'s first :req parameter
  #   on +klass+, or nil if it has none
  def first_required_param(klass, method_name)
    klass.instance_method(method_name).parameters.find { |type, _name| type == :req }&.last
  end

  describe "every BUILDERS method exists on the class it claims -- the guard" do
    it "resolves to a real public instance method for every entry" do
      each_descriptor do |component, method_name, descriptor|
        klass = klass_for(component, descriptor)

        expect(klass.public_method_defined?(method_name)).to be(true),
                                                               "#{component}: #{klass}##{method_name} " \
                                                               "does not exist"
      end
    end

    it "fires when a method name doesn't exist on the class (regression guard)" do
      broken = { "tabs" => { root: { "not_a_real_method" => { klass: "Component", arg: nil, block: nil } } } }

      offenders = each_descriptor(broken).reject do |component, method_name, descriptor|
        klass_for(component, descriptor).public_method_defined?(method_name)
      end

      expect(offenders.map { |_c, m, _d| m }).to eq(["not_a_real_method"])
    end
  end

  describe "every BUILDERS arg matches the method's first required positional parameter -- the guard" do
    it "matches instance_method(...).parameters for every entry" do
      each_descriptor do |component, method_name, descriptor|
        klass = klass_for(component, descriptor)
        actual = first_required_param(klass, method_name)

        expect(descriptor[:arg]).to eq(actual),
                                     "#{component}##{method_name}: BUILDERS says arg #{descriptor[:arg].inspect}, " \
                                     "method's first required param is #{actual.inspect}"
      end
    end

    it "fires when arg is recorded wrong (regression guard)" do
      broken = { "tabs" => { root: { "tab" => { klass: "Component", arg: :wrong_name, block: :children } } } }

      offenders = each_descriptor(broken).reject do |component, method_name, descriptor|
        klass = klass_for(component, descriptor)
        descriptor[:arg] == first_required_param(klass, method_name)
      end

      expect(offenders.map { |_c, m, _d| m }).to eq(["tab"])
    end

    it "fires when arg is recorded present but the method actually takes none (regression guard)" do
      broken = { "timeline" => { root: { "item" => { klass: "Component", arg: :title, block: :children } } } }

      offenders = each_descriptor(broken).reject do |component, method_name, descriptor|
        klass = klass_for(component, descriptor)
        descriptor[:arg] == first_required_param(klass, method_name)
      end

      expect(offenders.map { |_c, m, _d| m }).to eq(["item"])
    end
  end

  describe "BUILDERS vs. builder_style? components -- the guard" do
    def builder_style_components
      TablerUi::Docs::Navigation.components.select do |name|
        "TablerUi::#{name.camelize}::Component".constantize.builder_style?
      end.sort
    end

    it "covers exactly the components whose Component class declares builder_style!" do
      expect(described_class::BUILDERS.keys.sort).to eq(builder_style_components)
    end

    it "fires when a builder-style component is missing from BUILDERS (regression guard)" do
      broken = described_class::BUILDERS.reject { |name, _| name == "tabs" }

      expect(broken.keys.sort).not_to eq(builder_style_components)
      expect(builder_style_components).to include("tabs") # sanity: tabs really is builder-style
    end

    it "fires when a non-builder-style component is falsely added (regression guard)" do
      broken = described_class::BUILDERS.merge("card" => { root: {} })

      expect(broken.keys.sort).not_to eq(builder_style_components)
      expect(builder_style_components).not_to include("card") # sanity: card really isn't builder-style
    end

    it "fires when a component is listed under the wrong builder-style-ness entirely (regression guard)" do
      # Proves the equality check itself (not just key presence) would catch
      # a swap -- e.g. BUILDERS accidentally keyed by a typo'd/renamed component.
      broken = described_class::BUILDERS.keys.sort - ["navbar"] + ["navbar_typo"]

      expect(broken).not_to eq(builder_style_components)
    end
  end

  describe "navbar's nested levels" do
    it "root's left/right both nest into :group, on Component itself" do
      root = described_class.methods_for("navbar", :root)

      expect(root.keys.sort).to eq(%w[left right])
      expect(root["left"]).to include(klass: "Component", nests: :group)
      expect(root["right"]).to include(klass: "Component", nests: :group)
      expect(TablerUi::Navbar::Component.public_method_defined?(:left)).to be(true)
      expect(TablerUi::Navbar::Component.public_method_defined?(:right)).to be(true)
    end

    it "has a :group level matching NavigationGroup's real builder methods" do
      group = described_class.methods_for("navbar", :group)
      navigation_group = TablerUi::Navbar::Component::NavigationGroup

      expect(group.keys.sort).to eq(%w[add dark_mode_toggle divider dropdown])
      group.each_key { |method_name| expect(navigation_group.public_method_defined?(method_name)).to be(true) }
      expect(group["dropdown"]).to include(nests: :dropdown)
    end

    it "has a :dropdown level matching DropDownProxy's real builder methods" do
      dropdown = described_class.methods_for("navbar", :dropdown)
      drop_down_proxy = TablerUi::Navbar::Component::NavigationGroup::DropDownProxy

      expect(dropdown.keys.sort).to eq(%w[divider header item])
      dropdown.each_key { |method_name| expect(drop_down_proxy.public_method_defined?(method_name)).to be(true) }
    end

    it "every other component has only a :root level" do
      described_class::BUILDERS.except("navbar").each do |component, levels|
        expect(levels.keys).to eq([:root]), "#{component} has levels #{levels.keys.inspect}, expected just [:root]"
      end
    end
  end

  describe "BUILDERS" do
    it "is frozen, including every level Hash, method Hash, and descriptor" do
      expect(described_class::BUILDERS).to be_frozen

      described_class::BUILDERS.each_value do |levels|
        expect(levels).to be_frozen

        levels.each_value do |methods|
          expect(methods).to be_frozen

          methods.each_value { |descriptor| expect(descriptor).to be_frozen }
        end
      end
    end

    it "sorts its top-level component keys" do
      expect(described_class::BUILDERS.keys).to eq(described_class::BUILDERS.keys.sort)
    end
  end

  describe ".levels_for" do
    it "returns the levels Hash for a known component" do
      expect(described_class.levels_for("tabs").keys).to eq([:root])
      expect(described_class.levels_for("navbar").keys.sort).to eq(%i[dropdown group root])
    end

    it "returns {} for an unknown component, rather than nil or raising" do
      expect(described_class.levels_for("not_a_component")).to eq({})
    end
  end

  describe ".methods_for" do
    it "defaults to the :root level" do
      expect(described_class.methods_for("tabs").keys).to eq(["tab"])
    end

    it "accepts an explicit level" do
      expect(described_class.methods_for("navbar", :group).keys.sort).to eq(%w[add dark_mode_toggle divider dropdown])
    end

    it "returns {} for an unknown component or level, rather than nil or raising" do
      expect(described_class.methods_for("not_a_component")).to eq({})
      expect(described_class.methods_for("tabs", :nope)).to eq({})
    end
  end
end
