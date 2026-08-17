# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Ribbon", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:ribbon)

    expect(fragment.css("div.ribbon")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :ribbon, {},
    hook: :html, selector: ".ribbon"

  it "appends a caller class to the ribbon's own classes, not replacing them" do
    fragment = component_fragment(:ribbon, text: "New", color: "blue", html: { class: "hook-extra-class" })
    classes = fragment.css(".ribbon").first["class"].split(/\s+/)

    expect(classes).to include("ribbon", "bg-blue", "hook-extra-class")
  end

  it "renders text: as the ribbon's content" do
    fragment = component_fragment(:ribbon, text: "New")

    expect(fragment.css(".ribbon").first.text).to include("New")
  end

  it "renders a block instead of text: when both are given -- the block wins" do
    fragment = component_fragment(:ribbon, text: "New") do |slots|
      slots.body { "<strong>Rich</strong>".html_safe }
    end

    expect(fragment.css(".ribbon strong").first&.text).to eq("Rich")
    expect(fragment.css(".ribbon").first.text).not_to include("New")
  end

  it "adds bg-<color> for color:" do
    fragment = component_fragment(:ribbon, text: "New", color: "blue")

    expect(fragment.css(".ribbon").first["class"].split(/\s+/)).to include("bg-blue")
  end

  it "raises ArgumentError naming ribbon for an unknown color" do
    expect { component_fragment(:ribbon, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:ribbon, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /ribbon/)
  end

  it "adds ribbon-bottom for position: :bottom" do
    fragment = component_fragment(:ribbon, text: "New", position: :bottom)

    expect(fragment.css(".ribbon").first["class"].split(/\s+/)).to include("ribbon-bottom")
  end

  it "defaults to the top position -- no ribbon-bottom class, with or without an explicit position: :top" do
    fragment = component_fragment(:ribbon, text: "New")
    expect(fragment.css(".ribbon").first["class"].split(/\s+/)).not_to include("ribbon-bottom")

    fragment = component_fragment(:ribbon, text: "New", position: :top)
    expect(fragment.css(".ribbon").first["class"].split(/\s+/)).not_to include("ribbon-bottom")
  end

  it "raises ArgumentError for position: :start -- a ribbon sits top or bottom, never start or end" do
    expect { component_fragment(:ribbon, text: "New", position: :start) }
      .to raise_error(ArgumentError, /position/)
  end

  it "adds ribbon-start for align: :start" do
    fragment = component_fragment(:ribbon, text: "New", align: :start)

    expect(fragment.css(".ribbon").first["class"].split(/\s+/)).to include("ribbon-start")
  end

  it "adds no alignment class for align: :end -- the CSS's own default (base .ribbon sits on the right)" do
    fragment = component_fragment(:ribbon, text: "New", align: :end)
    classes = fragment.css(".ribbon").first["class"].split(/\s+/)

    expect(classes).not_to include("ribbon-start")
    expect(classes).not_to include("ribbon-end")
  end

  it "defaults align: to :end -- no ribbon-start class when align: is omitted" do
    fragment = component_fragment(:ribbon, text: "New")

    expect(fragment.css(".ribbon").first["class"].split(/\s+/)).not_to include("ribbon-start")
  end

  it "adds ribbon-bookmark for bookmark: true" do
    fragment = component_fragment(:ribbon, text: "New", bookmark: true)

    expect(fragment.css(".ribbon").first["class"].split(/\s+/)).to include("ribbon-bookmark")
  end

  it "renders a real icon through the dispatcher, not the error-fallback bug icon" do
    fragment = component_fragment(:ribbon, icon: "star", color: "yellow")

    expect(fragment.css(".ribbon svg")).not_to be_empty
    expect(fragment.css(".ribbon svg.icon-tabler-bug")).to be_empty
  end
end
