# frozen_string_literal: true

require "rails_helper"

# Proves the engine's config/locales/en.yml is actually picked up by the
# host app's I18n load path (Rails::Engine wires paths["config/locales"]
# into config.i18n.railties_load_path automatically -- no explicit
# initializer needed, see lib/tabler_ui/engine.rb). A missing translation
# renders as "translation missing: en.tabler_ui..." rather than raising, so
# this has to assert on the real, resolved text to catch a silently broken
# wiring.
RSpec.describe "TablerUi I18n" do
  it "loads the engine's locale file into I18n.load_path" do
    expect(I18n.load_path.any? { |path| path.to_s.end_with?("tabler_ui/config/locales/en.yml") }).to be(true)
  end

  it "resolves the form error notification translation" do
    expect(I18n.t("tabler_ui.form.error_notification")).to eq("Please review the following errors:")
  end

  it "resolves the illustration fallback translations" do
    expect(I18n.t("tabler_ui.illustration.not_found")).to eq("not found")
    expect(I18n.t("tabler_ui.illustration.unknown")).to eq("unknown")
  end

  it "resolves the dark mode toggle title translation" do
    expect(I18n.t("tabler_ui.dark_mode_toggle.title")).to eq("Switch theme")
  end
end
