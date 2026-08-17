# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Timeline", type: :component do
  it "renders with no arguments and no items, without raising" do
    fragment = component_fragment(:timeline)

    expect(fragment.css("ul.timeline")).not_to be_empty
    expect(fragment.css("li.timeline-event")).to be_empty
  end

  it "yields the component itself in builder style" do
    yielded = nil

    component_fragment(:timeline) do |t|
      yielded = t
    end

    expect(TablerUi::Timeline::Component.builder_style?).to be true
    expect(yielded).to respond_to(:item)
  end

  it "renders items in order with their block content inside .timeline-event-card" do
    fragment = component_fragment(:timeline) do |t|
      t.item { "First event" }
      t.item { "Second event" }
    end

    cards = fragment.css(".timeline-event-card")
    expect(cards.map { |c| c.text.strip }).to eq(["First event", "Second event"])
  end

  it "renders each item as an li.timeline-event inside ul.timeline" do
    fragment = component_fragment(:timeline) do |t|
      t.item { "Event" }
    end

    expect(fragment.css("ul.timeline > li.timeline-event").size).to eq(1)
  end

  it "adds timeline-simple for simple:" do
    fragment = component_fragment(:timeline, simple: true) do |t|
      t.item { "Event" }
    end

    expect(fragment.css("ul.timeline").first["class"].split(/\s+/)).to include("timeline-simple")
  end

  it "does not add timeline-simple by default" do
    fragment = component_fragment(:timeline) do |t|
      t.item { "Event" }
    end

    expect(fragment.css("ul.timeline").first["class"].split(/\s+/)).not_to include("timeline-simple")
  end

  it "renders icon: as a real icon, not the error-fallback bug icon" do
    fragment = component_fragment(:timeline) do |t|
      t.item(icon: "check") { "Done" }
    end

    svg = fragment.css(".timeline-event-icon svg").first
    expect(svg).not_to be_nil
    expect(svg["class"]).to include("icon-tabler-check")
    expect(svg["class"]).not_to include("icon-tabler-bug")
  end

  it "renders an item with no icon correctly -- an empty icon box, no error icon" do
    fragment = component_fragment(:timeline) do |t|
      t.item { "No icon here" }
    end

    icon_box = fragment.css(".timeline-event-icon").first
    expect(icon_box).not_to be_nil
    expect(icon_box.css("svg")).to be_empty
    expect(fragment.css(".timeline-event-card").first.text.strip).to eq("No icon here")
  end

  it "adds bg-<color>-lt to the icon box and colors the icon for color:" do
    fragment = component_fragment(:timeline) do |t|
      t.item(icon: "check", color: "blue") { "Done" }
    end

    icon_box = fragment.css(".timeline-event-icon").first
    expect(icon_box["class"].split(/\s+/)).to include("bg-blue-lt")

    svg = icon_box.css("svg").first
    expect(svg["class"]).to include("text-blue")
  end

  it "adds no bg-*-lt class when color: is omitted" do
    fragment = component_fragment(:timeline) do |t|
      t.item(icon: "check") { "Done" }
    end

    icon_box = fragment.css(".timeline-event-icon").first
    expect(icon_box["class"].split(/\s+/).grep(/\Abg-/)).to be_empty
  end

  it "raises ArgumentError naming timeline for an unknown color" do
    expect do
      component_fragment(:timeline) { |t| t.item(icon: "check", color: "not-a-real-color") { "Done" } }
    end.to raise_error(ArgumentError, /not-a-real-color/)

    expect do
      component_fragment(:timeline) { |t| t.item(icon: "check", color: "not-a-real-color") { "Done" } }
    end.to raise_error(ArgumentError, /timeline/)
  end

  it_behaves_like "an element with an html hook", :timeline, {}, hook: :html, selector: "ul.timeline"

  it "applies item_html: as a plain Hash to every item" do
    fragment = component_fragment(:timeline, item_html: { class: "all-items" }) do |t|
      t.item { "First" }
      t.item { "Second" }
    end
    items = fragment.css(".timeline-event")

    expect(items.size).to eq(2)
    items.each { |item| expect(item["class"].split(/\s+/)).to include("all-items") }
  end

  it "applies item_html: as a callable, so items can differ" do
    fragment = component_fragment(
      :timeline,
      item_html: ->(item) { { class: "highlight" } if item.icon == "check" }
    ) do |t|
      t.item(icon: "check") { "First" }
      t.item { "Second" }
    end
    items = fragment.css(".timeline-event")

    expect(items[0]["class"].split(/\s+/)).to include("highlight")
    expect(items[1]["class"].to_s).not_to include("highlight")
  end

  it "applies icon_html: to the right item only, as a plain Hash" do
    fragment = component_fragment(:timeline) do |t|
      t.item(icon: "check", icon_html: { class: "icon-highlight" }) { "First" }
      t.item(icon: "flag") { "Second" }
    end
    boxes = fragment.css(".timeline-event-icon")

    expect(boxes[0]["class"].split(/\s+/)).to include("icon-highlight")
    expect(boxes[1]["class"].to_s).not_to include("icon-highlight")
  end

  it "applies icon_html: to the right item only, as a callable taking the item" do
    fragment = component_fragment(:timeline) do |t|
      t.item(icon: "check", icon_html: ->(item) { { class: "icon-highlight" } if item.icon == "check" }) { "First" }
      t.item(icon: "flag", icon_html: ->(item) { { class: "icon-highlight" } if item.icon == "check" }) { "Second" }
    end
    boxes = fragment.css(".timeline-event-icon")

    expect(boxes[0]["class"].split(/\s+/)).to include("icon-highlight")
    expect(boxes[1]["class"].to_s).not_to include("icon-highlight")
  end

  it "applies card_html: to the right item only, as a plain Hash" do
    fragment = component_fragment(:timeline) do |t|
      t.item(card_html: { class: "card-highlight" }) { "First" }
      t.item { "Second" }
    end
    cards = fragment.css(".timeline-event-card")

    expect(cards[0]["class"].split(/\s+/)).to include("card-highlight")
    expect(cards[1]["class"].to_s).not_to include("card-highlight")
  end

  it "applies card_html: to the right item only, as a callable taking the item" do
    fragment = component_fragment(:timeline) do |t|
      t.item(icon: "check", card_html: ->(item) { { class: "card-highlight" } if item.icon == "check" }) { "First" }
      t.item(card_html: ->(item) { { class: "card-highlight" } if item.icon == "check" }) { "Second" }
    end
    cards = fragment.css(".timeline-event-card")

    expect(cards[0]["class"].split(/\s+/)).to include("card-highlight")
    expect(cards[1]["class"].to_s).not_to include("card-highlight")
  end
end
