# frozen_string_literal: true

require "rails_helper"

RSpec.describe TablerUi::CssBundle do
  let(:stylesheets_dir) do
    File.expand_path("../../../app/assets/stylesheets", __dir__)
  end
  let(:committed_bundle_path) { File.join(stylesheets_dir, "tabler_ui_all.css") }
  let(:manifest_path) { File.join(stylesheets_dir, "tabler_ui.css") }

  it "matches the committed tabler_ui_all.css byte for byte" do
    # .b forces a binary comparison: File.binread returns ASCII-8BIT while
    # .generate returns UTF-8, so plain String#== would report a mismatch on
    # any multibyte character even when every byte is identical.
    expect(File.binread(committed_bundle_path)).to eq(described_class.generate.b)
  end

  it "resolves exactly the *= require lines in tabler_ui.css, in the same order" do
    manifest = File.read(manifest_path)
    required = manifest.scan(/^\s\*= require\s+(\S+)/).flatten
    resolved = described_class::SOURCES.map { |source| source.sub(/\.css\z/, "") }

    expect(resolved).to eq(required)
  end

  it "contains real CSS rules, not just the manifest's comments" do
    bundle = described_class.generate

    expect(bundle).to include(".alert {")

    without_comments = bundle.gsub(%r{/\*.*?\*/}m, "").strip
    expect(without_comments).not_to be_empty
  end
end
