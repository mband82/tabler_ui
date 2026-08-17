# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::DarkModeToggle", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:dark_mode_toggle)

    expect(fragment.css("div > a")).not_to be_empty
    expect(fragment.css("svg").size).to eq(3)
  end

  it_behaves_like "an element with an html hook", :dark_mode_toggle, {},
    hook: :html, selector: "div.d-inline-block"

  it_behaves_like "an element with an html hook", :dark_mode_toggle, {},
    hook: :link_html, selector: "a.nav-link.px-0"

  it "appends a caller class to the outer div's own class, not replacing it" do
    fragment = component_fragment(:dark_mode_toggle, html: { class: "hook-extra-class" })
    classes = fragment.css("div").first["class"].split(/\s+/)

    expect(classes).to include("d-inline-block", "hook-extra-class")
  end

  it "appends a caller class to the anchor's own classes, keeping nav-link px-0" do
    fragment = component_fragment(:dark_mode_toggle, link_html: { class: "hook-extra-class" })
    classes = fragment.css("a").first["class"].split(/\s+/)

    expect(classes).to include("nav-link", "px-0", "hook-extra-class")
  end

  it "keeps the tabler-ui--dark-mode Stimulus controller on the root div" do
    fragment = component_fragment(:dark_mode_toggle)

    expect(fragment.css("div").first["data-controller"]).to eq("tabler-ui--dark-mode")
  end

  it "keeps the click->toggle action on the anchor" do
    fragment = component_fragment(:dark_mode_toggle)

    expect(fragment.css("a").first["data-action"]).to eq("click->tabler-ui--dark-mode#toggle")
  end

  it "keeps the light/dark/system Stimulus targets, in that order" do
    fragment = component_fragment(:dark_mode_toggle)
    svgs = fragment.css("svg")

    expect(svgs.map { |svg| svg["data-tabler-ui--dark-mode-target"] }).to eq(%w[light dark system])
  end

  it "keeps d-none on the dark and system icons but not the light one" do
    fragment = component_fragment(:dark_mode_toggle)
    svgs = fragment.css("svg")

    expect(svgs[0]["class"].split(/\s+/)).not_to include("d-none")
    expect(svgs[1]["class"].split(/\s+/)).to include("d-none")
    expect(svgs[2]["class"].split(/\s+/)).to include("d-none")
  end

  it "defaults the SVG icon size to 24" do
    fragment = component_fragment(:dark_mode_toggle)

    expect(fragment.css("svg").first["width"]).to eq("24")
    expect(fragment.css("svg").first["height"]).to eq("24")
  end

  it "uses 16px icons for size: :sm" do
    fragment = component_fragment(:dark_mode_toggle, size: :sm)

    expect(fragment.css("svg").first["width"]).to eq("16")
    expect(fragment.css("svg").first["height"]).to eq("16")
  end

  it "uses 32px icons for size: :lg" do
    fragment = component_fragment(:dark_mode_toggle, size: :lg)

    expect(fragment.css("svg").first["width"]).to eq("32")
    expect(fragment.css("svg").first["height"]).to eq("32")
  end

  it "defaults the anchor's title to the translated 'Switch theme'" do
    fragment = component_fragment(:dark_mode_toggle)

    expect(fragment.css("a").first["title"]).to eq("Switch theme")
  end

  it "renders a custom title: on the anchor" do
    fragment = component_fragment(:dark_mode_toggle, title: "Switch theme")

    expect(fragment.css("a").first["title"]).to eq("Switch theme")
  end
end
