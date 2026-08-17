# frozen_string_literal: true

require "rails_helper"

RSpec.describe TablerUi::Breakpoint do
  describe ".validate!" do
    TablerUi::Breakpoint::ALL.each do |breakpoint|
      it "accepts #{breakpoint.inspect} and returns it as a String" do
        result = described_class.validate!(breakpoint)

        expect(result).to eq(breakpoint)
        expect(result).to be_a(String)
      end
    end

    it "returns nil for nil -- the breakpoint is optional" do
      expect(described_class.validate!(nil)).to be_nil
    end

    it "raises ArgumentError mentioning the offending value for an unknown breakpoint" do
      expect { described_class.validate!("xs") }
        .to raise_error(ArgumentError, /xs/)
    end

    it "includes the context in the error message when given" do
      expect { described_class.validate!("xs", context: "sidebar") }
        .to raise_error(ArgumentError, /sidebar/)
    end
  end

  describe ".valid?" do
    it "is true for nil" do
      expect(described_class.valid?(nil)).to be(true)
    end

    it "is true for every valid breakpoint" do
      TablerUi::Breakpoint::ALL.each do |breakpoint|
        expect(described_class.valid?(breakpoint)).to be(true)
      end
    end

    it "is false for an unknown breakpoint" do
      expect(described_class.valid?("xs")).to be(false)
    end
  end
end
