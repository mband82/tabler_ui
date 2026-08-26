# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor/slot_map"

# The point of this spec is the same symmetric check navigation_spec.rb runs
# for CATEGORIES: SlotMap::SLOTS is hand-maintained (see the module doc for
# why -- docs/lib is not autoloaded or reloaded, so deriving it at load time
# would only ever reflect server-boot state anyway), so this spec re-derives
# the truth fresh, at runtime, by globbing and grepping the component
# templates directly, and asserts it against the constant. A component
# gaining, losing, or renaming a slot -- or a 14th component starting to use
# slots -- must fail this spec, not go unnoticed.
RSpec.describe TablerUi::Docs::Editor::SlotMap do
  # Real methods TablerUi::SlotContext (lib/tabler_ui/ui.rb) responds to
  # besides the dynamic slot accessors reached through method_missing --
  # calls on the SlotContext object itself, not slot names, so a template
  # calling `slots.present?` or `slots.empty?` must not be mistaken for a
  # slot named "present" or "empty".
  SLOT_CONTEXT_OWN_METHODS = %w[present? empty?].freeze

  COMPONENTS_ROOT = File.expand_path("../../../../../app/components/tabler_ui", __dir__)

  def derive_slots
    Dir.glob(File.join(COMPONENTS_ROOT, "*", "_component.html.erb")).each_with_object({}) do |path, result|
      component = File.basename(File.dirname(path))
      source = File.read(path)

      names = source.scan(/slots\.([a-zA-Z_][a-zA-Z0-9_?!]*)/)
                     .flatten
                     .reject { |name| SLOT_CONTEXT_OWN_METHODS.include?(name) }
                     .uniq
                     .sort

      result[component] = names if names.any?
    end
  end

  describe "SLOTS vs. the component templates -- the guard" do
    it "matches a fresh derivation from disk exactly" do
      derived = derive_slots

      expect(described_class::SLOTS.keys.sort).to eq(derived.keys.sort)

      derived.each do |component, names|
        expect(described_class::SLOTS[component]).to eq(names),
                                                       "expected #{component.inspect} slots to be #{names.inspect}, " \
                                                       "got #{described_class::SLOTS[component].inspect}"
      end
    end

    it "does not list a component whose template takes no slots.* calls" do
      derived = derive_slots
      slotless = all_component_names - derived.keys

      expect(slotless).not_to be_empty # sanity: the 22 slot-less components exist
      expect(described_class::SLOTS.keys & slotless).to eq([])
    end

    it "excludes SlotContext's own methods (present?, empty?) from every slot list" do
      described_class::SLOTS.each_value do |names|
        expect(names).not_to include(*SLOT_CONTEXT_OWN_METHODS)
      end
    end

    it "sorts keys and, within each component, sorts slot names" do
      expect(described_class::SLOTS.keys).to eq(described_class::SLOTS.keys.sort)

      described_class::SLOTS.each_value do |names|
        expect(names).to eq(names.sort)
      end
    end

    it "fires when a component gains an untracked slot (regression guard)" do
      # Proves the comparison above actually catches drift rather than
      # vacuously passing -- mutates a duplicate, not the frozen constant.
      broken = described_class::SLOTS.transform_values(&:dup)
      broken["card"] << "sidebar"

      derived = derive_slots

      expect(broken["card"]).not_to eq(derived["card"])
    end

    it "fires when a component loses a real slot (regression guard)" do
      broken = described_class::SLOTS.transform_values(&:dup)
      broken["modal"].delete("footer")

      derived = derive_slots

      expect(broken["modal"]).not_to eq(derived["modal"])
    end

    it "fires when a slot-less component is falsely added (regression guard)" do
      broken = described_class::SLOTS.dup
      broken["button"] = %w[body]

      derived = derive_slots

      expect(broken.keys.sort).not_to eq(derived.keys.sort)
    end

    def all_component_names
      Dir.glob(File.join(COMPONENTS_ROOT, "*", "_component.html.erb"))
         .map { |path| File.basename(File.dirname(path)) }
    end
  end

  describe "SLOTS" do
    it "is frozen, including every value array" do
      expect(described_class::SLOTS).to be_frozen

      described_class::SLOTS.each_value do |names|
        expect(names).to be_frozen
      end
    end
  end

  describe ".slots_for" do
    it "returns the slot names for a known slotted component" do
      expect(described_class.slots_for("card")).to eq(%w[body footer header])
    end

    it "accepts a Symbol as well as a String" do
      expect(described_class.slots_for(:alert)).to eq(%w[body])
    end

    it "returns an empty array for a real component with no slots, rather than nil" do
      expect(described_class.slots_for("button")).to eq([])
    end

    it "returns an empty array for an unknown component name, rather than raising" do
      expect(described_class.slots_for("not_a_component")).to eq([])
    end
  end
end
