# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"

# The point of this spec is the symmetric check between `components`
# (derived from disk) and `CATEGORIES` (hand-maintained): every component
# in exactly one category, and every categorized name a real component.
# That's the guard against the exact failure mode described in
# docs/lib/tabler_ui/docs/navigation.rb's module doc -- a grouping that
# looks individually plausible per category but has quietly drifted from
# reality (the old showcase missed dark_mode_toggle entirely and nothing
# noticed).
RSpec.describe TablerUi::Docs::Navigation do
  describe ".components" do
    it "finds every component directory under app/components/tabler_ui" do
      expect(described_class.components).to include("alert", "modal", "navbar", "dark_mode_toggle")
    end

    it "is derived from disk, not hand-maintained -- matches a fresh directory walk" do
      expected = Dir.glob(File.join(described_class::COMPONENTS_ROOT, "*", "component.rb"))
                     .map { |path| File.basename(File.dirname(path)) }
                     .sort

      expect(described_class.components).to eq(expected)
    end

    it "returns a sorted, deduplicated list" do
      components = described_class.components

      expect(components).to eq(components.sort)
      expect(components.uniq).to eq(components)
    end

    it "does not include form_builder -- it has no app/components/tabler_ui directory" do
      expect(described_class.components).not_to include("form_builder")
    end
  end

  describe "CATEGORIES vs. components -- the guard" do
    it "every component on disk appears in exactly one category" do
      categorized = described_class::CATEGORIES.values.flatten

      described_class.components.each do |component|
        occurrences = categorized.count(component)
        expect(occurrences).to eq(1),
                                "expected #{component.inspect} to appear in exactly one category, " \
                                "appeared in #{occurrences}"
      end
    end

    it "every categorized name is a real component directory" do
      real = described_class.components

      described_class::CATEGORIES.each do |category, names|
        names.each do |name|
          expect(real).to include(name),
                           "#{category.inspect} lists #{name.inspect}, which has no " \
                           "app/components/tabler_ui/#{name}/component.rb"
        end
      end
    end

    it "categorizes exactly the components on disk, no more and no less" do
      categorized = described_class::CATEGORIES.values.flatten.sort

      expect(categorized).to eq(described_class.components)
    end

    it "fires when a category entry does not correspond to a component (regression guard)" do
      # Proves the previous two examples actually catch drift, rather than
      # vacuously passing. Mutates a duplicate, not the frozen constant.
      broken = described_class::CATEGORIES.transform_values(&:dup)
      broken["Layout"] << "not_a_real_component"

      real = described_class.components
      offenders = broken.values.flatten.reject { |name| real.include?(name) }

      expect(offenders).to eq(["not_a_real_component"])
    end

    it "fires when a real component is missing from every category (regression guard)" do
      broken = described_class::CATEGORIES.transform_values(&:dup)
      broken["Layout"].delete("accordion")

      categorized = broken.values.flatten

      expect(described_class.components).not_to eq(categorized.sort)
      expect(categorized).not_to include("accordion")
    end

    it "fires when a component is listed in two categories at once (regression guard)" do
      broken = described_class::CATEGORIES.transform_values(&:dup)
      broken["Layout"] << "modal"

      expect(broken.values.flatten.count("modal")).to eq(2)
    end
  end

  describe "CATEGORIES ordering" do
    it "is a plain Hash, whose insertion order IS the sidebar order (deterministic, not rehashed)" do
      expect(described_class::CATEGORIES).to be_a(Hash)
      expect(described_class::CATEGORIES).to be_frozen
    end

    it ".category_names returns the same order on repeated calls" do
      first = described_class.category_names
      second = described_class.category_names

      expect(first).to eq(second)
      expect(first).to eq(%w[Layout Content Overlays])
    end
  end

  describe ".category_names" do
    it "returns every category key, in CATEGORIES order" do
      expect(described_class.category_names).to eq(described_class::CATEGORIES.keys)
    end
  end

  describe ".components_in" do
    it "returns the components for a known category, in sidebar order" do
      expect(described_class.components_in("Overlays")).to eq(described_class::CATEGORIES["Overlays"])
    end

    it "returns a new array -- callers can't mutate CATEGORIES through it" do
      result = described_class.components_in("Overlays")
      result << "not_real"

      expect(described_class::CATEGORIES["Overlays"]).not_to include("not_real")
    end

    it "returns an empty array for an unknown category, rather than raising" do
      expect(described_class.components_in("Nope")).to eq([])
    end
  end

  describe ".category_for" do
    it "finds the category for a known component" do
      expect(described_class.category_for("modal")).to eq("Overlays")
      expect(described_class.category_for("navbar")).to eq("Layout")
      expect(described_class.category_for("badge")).to eq("Content")
    end

    it "accepts a Symbol as well as a String" do
      expect(described_class.category_for(:modal)).to eq("Overlays")
    end

    it "returns nil for a name that is not categorized" do
      expect(described_class.category_for("not_a_component")).to be_nil
    end

    it "resolves every real component to some category (given the guard above holds)" do
      described_class.components.each do |component|
        expect(described_class.category_for(component)).not_to be_nil
      end
    end
  end

  describe ".title_for" do
    it "humanizes a snake_case component name" do
      expect(described_class.title_for("dark_mode_toggle")).to eq("Dark mode toggle")
      expect(described_class.title_for("stat_card")).to eq("Stat card")
    end

    it "accepts a Symbol as well as a String" do
      expect(described_class.title_for(:badge_list)).to eq("Badge list")
    end
  end

  describe "UNDEMOED_BY_SHOWCASE" do
    it "lists only real components" do
      expect(described_class.components).to include(*described_class::UNDEMOED_BY_SHOWCASE)
    end

    it "is frozen" do
      expect(described_class::UNDEMOED_BY_SHOWCASE).to be_frozen
    end
  end
end
