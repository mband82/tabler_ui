# frozen_string_literal: true

require "rails_helper"

RSpec.describe TablerUi::UsageDoc do
  let(:expected_titles) do
    TablerUi::Docs::Navigation.components.map { |name| TablerUi::Docs::Navigation.title_for(name) }
  end

  it "generates a String" do
    expect(described_class.generate).to be_a(String)
  end

  it "documents every real component by its humanized title" do
    expect(described_class.generate).to include(*expected_titles)
  end

  it "includes a Form builder section" do
    expect(described_class.generate).to include("## Form builder")
  end

  it "includes the install gem line" do
    expect(described_class.generate).to include('gem "tabler_ui"')
  end

  it "matches the committed USAGE.md byte for byte" do
    expect(File.binread(described_class::PATH)).to eq(described_class.generate.b)
  end
end
