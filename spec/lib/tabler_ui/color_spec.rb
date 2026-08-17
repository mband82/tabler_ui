# frozen_string_literal: true

require "rails_helper"

RSpec.describe TablerUi::Color do
  describe ".validate!" do
    it "accepts every ALL value with no extra:" do
      TablerUi::Color::ALL.each do |color|
        expect(described_class.validate!(color)).to eq(color)
      end
    end

    it "returns nil for nil -- colour is optional" do
      expect(described_class.validate!(nil)).to be_nil
    end

    it "raises ArgumentError naming the offender for an unknown color" do
      expect { described_class.validate!("not-a-color") }
        .to raise_error(ArgumentError, /not-a-color/)
    end

    it "rejects a brand color when no extra: is given" do
      expect { described_class.validate!("facebook") }
        .to raise_error(ArgumentError, /facebook/)
    end

    it "accepts a brand color when passed in via extra: BRAND" do
      expect(described_class.validate!("facebook", extra: TablerUi::Color::BRAND)).to eq("facebook")
    end

    it "accepts muted when passed in via extra: MUTED" do
      expect(described_class.validate!("muted", extra: TablerUi::Color::MUTED)).to eq("muted")
    end

    it "rejects muted when no extra: is given" do
      expect { described_class.validate!("muted") }
        .to raise_error(ArgumentError, /muted/)
    end

    it "lists ALL plus extra in the error message, not just ALL" do
      expect { described_class.validate!("not-a-color", extra: TablerUi::Color::BRAND) }
        .to raise_error(ArgumentError, /facebook/)
    end
  end

  describe ".valid?" do
    it "is true for every ALL value" do
      TablerUi::Color::ALL.each do |color|
        expect(described_class.valid?(color)).to be(true)
      end
    end

    it "is false for a brand color with no extra:" do
      expect(described_class.valid?("facebook")).to be(false)
    end

    it "is true for a brand color when passed in via extra:" do
      expect(described_class.valid?("facebook", extra: TablerUi::Color::BRAND)).to be(true)
    end
  end

  describe "ALL" do
    it "does not include any BRAND color -- brand colors are opt-in per component" do
      expect(TablerUi::Color::ALL & TablerUi::Color::BRAND).to be_empty
    end

    it "does not include muted -- muted is opt-in per component" do
      expect(TablerUi::Color::ALL).not_to include("muted")
    end
  end
end
