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

  # CLAUDE.md rule 8: the `auth:` option, gated inside Timeline::Component#item.
  # TablerUi.auth_method is global, process-wide mutable state -- restore it
  # after every example so a custom auth_method here never leaks into specs
  # that run afterward (see spec/lib/tabler_ui/authorization_spec.rb's
  # identical around block for the same reasoning).
  describe "auth: gating on items" do
    around do |example|
      original = TablerUi.auth_method
      example.run
      TablerUi.auth_method = original
    end

    it "renders exactly as before with the default auth_method and no auth: anywhere" do
      fragment = component_fragment(:timeline) do |t|
        t.item(icon: "check") { "First" }
        t.item(icon: "flag") { "Second" }
      end

      cards = fragment.css(".timeline-event-card")
      expect(cards.map { |c| c.text.strip }).to eq(["First", "Second"])
    end

    it "omits an item whose own auth: is denied" do
      TablerUi.auth_method = ->(value) { value != :forbidden }

      fragment = component_fragment(:timeline) do |t|
        t.item(auth: :forbidden) { "Hidden" }
        t.item(auth: :allowed) { "Visible" }
      end

      cards = fragment.css(".timeline-event-card")
      expect(cards.map { |c| c.text.strip }).to eq(["Visible"])
    end

    it "includes an item whose own auth: is authorized" do
      TablerUi.auth_method = ->(value) { value != :forbidden }

      fragment = component_fragment(:timeline) do |t|
        t.item(auth: :allowed) { "Visible" }
      end

      cards = fragment.css(".timeline-event-card")
      expect(cards.map { |c| c.text.strip }).to eq(["Visible"])
    end

    it "allows an item with no auth: of its own when the timeline's own auth: is allowed" do
      TablerUi.auth_method = ->(value) { value == :allowed }

      fragment = component_fragment(:timeline, auth: :allowed) do |t|
        t.item { "Visible" }
      end

      cards = fragment.css(".timeline-event-card")
      expect(cards.map { |c| c.text.strip }).to eq(["Visible"])
    end

    it "lets an item's own auth: override an allowing parent auth:" do
      TablerUi.auth_method = ->(value) { value != :forbidden }

      fragment = component_fragment(:timeline, auth: :allowed) do |t|
        t.item(auth: :forbidden) { "Hidden" }
      end

      expect(fragment.css(".timeline-event-card")).to be_empty
    end

    # The two cases above can't be exercised through the full `tabler_ui.timeline`
    # dispatch when the *parent's* own auth: is the one being denied: Ui#method_missing
    # gates the entire top-level call on that same value (lib/tabler_ui/ui.rb) before
    # the block -- and so `#item` -- ever runs, so a denied parent means nothing
    # renders at all, item-level auth: never gets a chance to matter either way. (A
    # sibling spec for another builder component made exactly this mistake -- asserting
    # an item's own auth: could "rescue" a denied parent through full dispatch -- and it
    # fails for that reason.) These call Component#item directly, with auth= set the
    # way Ui#method_missing sets it after a *successful* dispatch, to test the
    # inheritance/override logic in #item in isolation from that outer gate.
    describe "inheritance/override logic in #item, exercised directly on the component" do
      it "an item with no auth: of its own inherits a denied timeline-level auth: and is omitted" do
        TablerUi.auth_method = ->(value) { value != :forbidden }
        timeline = TablerUi::Timeline::Component.new
        timeline.auth = :forbidden

        timeline.item { "Hidden" }

        expect(timeline.items).to be_empty
      end

      it "an item with no auth: of its own inherits an allowed timeline-level auth: and is kept" do
        TablerUi.auth_method = ->(value) { value == :allowed }
        timeline = TablerUi::Timeline::Component.new
        timeline.auth = :allowed

        timeline.item { "Visible" }

        expect(timeline.items.size).to eq(1)
        expect(timeline.items.first.auth).to eq(:allowed)
      end

      it "an item's own auth: overrides a denied timeline-level auth:" do
        TablerUi.auth_method = ->(value) { value == :allowed }
        timeline = TablerUi::Timeline::Component.new
        timeline.auth = :forbidden

        timeline.item(auth: :allowed) { "Visible" }

        expect(timeline.items.size).to eq(1)
        expect(timeline.items.first.auth).to eq(:allowed)
      end
    end
  end

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
