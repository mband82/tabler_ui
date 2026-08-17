# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::SettingsPage", type: :component do
  it "renders with just the mandatory id" do
    fragment = component_fragment(:settings_page, "my-settings")

    expect(fragment.css(".card")).not_to be_empty
  end

  it "raises ArgumentError naming the component when id is missing" do
    expect { component_fragment(:settings_page) }
      .to raise_error(ArgumentError, /tabler_ui\.settings_page requires id/)
  end

  it "yields the component itself, in builder style" do
    expect(TablerUi::SettingsPage::Component.builder_style?).to be(true)

    yielded = nil
    component_fragment(:settings_page, "my-settings") do |sp|
      yielded = sp
    end

    expect(yielded).to be_a(TablerUi::SettingsPage::Component)
    expect(yielded).to respond_to(:item)
  end

  it "renders multiple items, each with its content block captured" do
    fragment = component_fragment(:settings_page, "my-settings") do |sp|
      sp.item("General") { "General content" }
      sp.item("Security") { "Security content" }
    end

    expect(fragment.css(".list-group-item").map(&:text).map(&:strip)).to eq(%w[General Security])
    expect(fragment.css(".tab-pane")[0].text.strip).to eq("General content")
    expect(fragment.css(".tab-pane")[1].text.strip).to eq("Security content")
  end

  it "marks one item and its pane active: with active:" do
    fragment = component_fragment(:settings_page, "my-settings") do |sp|
      sp.item("General", active: false) { "General content" }
      sp.item("Security", active: true) { "Security content" }
    end

    list_items = fragment.css(".list-group-item")
    panes = fragment.css(".tab-pane")

    expect(list_items[0]["class"].split(/\s+/)).not_to include("active")
    expect(list_items[1]["class"].split(/\s+/)).to include("active")

    expect(panes[0]["class"].split(/\s+/)).not_to include("active")
    expect(panes[1]["class"].split(/\s+/)).to include("active", "show")
  end

  it "defaults the first item to active when active: is not given" do
    fragment = component_fragment(:settings_page, "my-settings") do |sp|
      sp.item("General") { "General content" }
      sp.item("Security") { "Security content" }
    end

    list_items = fragment.css(".list-group-item")

    expect(list_items[0]["class"].split(/\s+/)).to include("active")
    expect(list_items[1]["class"].split(/\s+/)).not_to include("active")
  end

  it "renders a real icon for icon:, not the error-fallback bug icon" do
    fragment = component_fragment(:settings_page, "my-settings") do |sp|
      sp.item("General", icon: "settings") { "Content" }
    end

    svg = fragment.css(".list-group-item svg").first
    expect(svg).not_to be_nil
    expect(svg["class"].to_s.split(/\s+/)).not_to include("icon-tabler-bug")
  end

  it_behaves_like "an element with an html hook", :settings_page, { id: "my-settings" },
    hook: :html, selector: ".card"

  it_behaves_like "an element with an html hook", :settings_page, { id: "my-settings" },
    hook: :sidebar_html, selector: ".col-md-3"

  it_behaves_like "an element with an html hook", :settings_page, { id: "my-settings" },
    hook: :content_html, selector: ".col-md-9"

  it "applies per-item html: to that item only, via a plain Hash" do
    fragment = component_fragment(:settings_page, "my-settings") do |sp|
      sp.item("General", html: { class: "hook-extra-class", id: "hook-test-id" }) { "Content" }
      sp.item("Security") { "Content" }
    end

    list_items = fragment.css(".list-group-item")

    expect(list_items[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(list_items[0]["id"]).to eq("hook-test-id")
    expect(list_items[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
    expect(list_items[1]["id"]).to be_nil
  end

  it "applies per-item html: to that item only, via a callable taking the item" do
    fragment = component_fragment(:settings_page, "my-settings") do |sp|
      sp.item("General", html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }) { "Content" }
      sp.item("Security", html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }) { "Content" }
    end

    list_items = fragment.css(".list-group-item")

    expect(list_items[0]["class"].split(/\s+/)).to include("callable-class-general")
    expect(list_items[0]["class"].split(/\s+/)).not_to include("callable-class-security")
    expect(list_items[1]["class"].split(/\s+/)).to include("callable-class-security")
    expect(list_items[1]["class"].split(/\s+/)).not_to include("callable-class-general")
  end

  it "renders title: above the sidebar navigation" do
    fragment = component_fragment(:settings_page, "my-settings", title: "Preferences") do |sp|
      sp.item("General") { "Content" }
    end

    expect(fragment.css(".subheader").text.strip).to eq("Preferences")
  end

  it "defaults title: to 'Settings' when omitted" do
    fragment = component_fragment(:settings_page, "my-settings") do |sp|
      sp.item("General") { "Content" }
    end

    expect(fragment.css(".subheader").text.strip).to eq("Settings")
  end
end
