# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Card", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:card)

    expect(fragment.css(".card")).not_to be_empty
    expect(fragment.css(".card-header")).to be_empty
    expect(fragment.css(".card-body")).to be_empty
    expect(fragment.css(".card-footer")).to be_empty
  end

  # Regression: _card.html.erb:6 used to do
  # `card.respond_to?(:class) ? card.class : ''` -- every Ruby object
  # responds to :class, so that always took the true branch and returned the
  # *Ruby Class object* (an OpenStruct, since the bare partial wrapped
  # kwargs in one), producing a literal "OpenStruct" token in the rendered
  # class list and silently discarding any caller-supplied `class:`. The
  # conversion to a real component class plus the rule 5 `html:` hook
  # removes the OpenStruct entirely, so this can no longer happen.
  it "does not leak the OpenStruct class name and keeps the caller's class via html:" do
    fragment = component_fragment(:card, html: { class: "shadow-sm" })
    element = fragment.css(".card").first

    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("shadow-sm")
    expect(classes).not_to include("OpenStruct")
    expect(fragment.to_html).not_to include("OpenStruct")
  end

  it_behaves_like "an element with an html hook", :card, {},
    hook: :html, selector: ".card"

  it_behaves_like "an element with an html hook", :card, { title: "Card title" },
    hook: :header_html, selector: ".card-header"

  it "passes id/data/class through body_html: onto the .card-body" do
    fragment = component_fragment(:card, body_html: { class: "hook-extra-class", id: "hook-test-id",
                                                        data: { testid: "hook-test-data" } }) do |slots|
      slots.body { "Content" }
    end
    element = fragment.css(".card-body").first

    expect(element).not_to be_nil
    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("card-body", "hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it "passes id/data/class through footer_html: onto the .card-footer" do
    fragment = component_fragment(:card, footer_html: { class: "hook-extra-class", id: "hook-test-id",
                                                          data: { testid: "hook-test-data" } }) do |slots|
      slots.footer { "Content" }
    end
    element = fragment.css(".card-footer").first

    expect(element).not_to be_nil
    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("card-footer", "hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it "renders the header, body and footer slots' content" do
    fragment = component_fragment(:card) do |slots|
      slots.header { "Header content" }
      slots.body { "Body content" }
      slots.footer { "Footer content" }
    end

    expect(fragment.css(".card-header").text.strip).to eq("Header content")
    expect(fragment.css(".card-body").text.strip).to eq("Body content")
    expect(fragment.css(".card-footer").text.strip).to eq("Footer content")
  end

  it "renders no header/body/footer wrapper when the corresponding slot is omitted" do
    fragment = component_fragment(:card) do |slots|
      slots.body { "Body content" }
    end

    expect(fragment.css(".card-header")).to be_empty
    expect(fragment.css(".card-body")).not_to be_empty
    expect(fragment.css(".card-footer")).to be_empty
  end

  it "renders title: as an h3.card-title inside the header when no header slot is given" do
    fragment = component_fragment(:card, title: "Card title")

    expect(fragment.css(".card-header h3.card-title").text).to eq("Card title")
  end

  it "renders the header when only title: is present (no slots at all)" do
    fragment = component_fragment(:card, title: "Card title")

    expect(fragment.css(".card-header")).not_to be_empty
  end

  it "renders the header when a header slot is present, even without title:" do
    fragment = component_fragment(:card) do |slots|
      slots.header { "Custom header" }
    end

    expect(fragment.css(".card-header")).not_to be_empty
  end

  it "prefers a header slot over title: when both are given" do
    fragment = component_fragment(:card, title: "Ignored title") do |slots|
      slots.header { "Custom header".html_safe }
    end

    expect(fragment.css(".card-header").text.strip).to eq("Custom header")
    expect(fragment.css(".card-header h3.card-title")).to be_empty
    expect(fragment.to_html).not_to include("Ignored title")
  end

  it "adds card-<size> for size:" do
    fragment = component_fragment(:card, size: "lg")

    expect(fragment.css(".card").first["class"].split(/\s+/)).to include("card-lg")
  end

  # Regression: status: used to add "card-status-top"/"bg-<color>" to the
  # .card root itself. tabler.css's .card-status-top is a bare selector
  # (absolute, 2px tall) meant for a dedicated empty child div -- applied to
  # .card directly it collapsed the whole card into a 2px sliver. The strip
  # must be a separate child element, and .card must carry neither class.
  it "renders the status strip as a separate empty child, not classes on .card" do
    fragment = component_fragment(:card, status: "primary")

    card_classes = fragment.css(".card").first["class"].split(/\s+/)
    expect(card_classes).not_to include(a_string_matching(/\Acard-status-/))
    expect(card_classes).not_to include("bg-primary")

    strips = fragment.css(".card > .card-status-top")
    expect(strips.size).to eq(1)
    strip = strips.first
    expect(strip["class"].split(/\s+/)).to contain_exactly("card-status-top", "bg-primary")
    expect(strip.text.strip).to eq("")
    expect(strip.children).to be_empty
  end

  it "renders no status strip at all when status: is omitted" do
    fragment = component_fragment(:card)

    expect(fragment.to_html).not_to include("card-status-")
  end

  it "defaults status_position: to top" do
    fragment = component_fragment(:card, status: "blue")

    expect(fragment.css(".card-status-top.bg-blue")).not_to be_empty
  end

  it "emits card-status-start for status_position: 'start'" do
    fragment = component_fragment(:card, status: "blue", status_position: "start")

    expect(fragment.css(".card-status-start.bg-blue")).not_to be_empty
    expect(fragment.css(".card-status-top")).to be_empty
  end

  it "emits card-status-bottom for status_position: 'bottom'" do
    fragment = component_fragment(:card, status: "blue", status_position: "bottom")

    expect(fragment.css(".card-status-bottom.bg-blue")).not_to be_empty
    expect(fragment.css(".card-status-top")).to be_empty
  end

  it "is a no-op when status_position: is given without status:" do
    fragment = component_fragment(:card, status_position: "start")

    expect(fragment.to_html).not_to include("card-status-")
  end

  it "raises ArgumentError naming card for an unknown status color" do
    expect { component_fragment(:card, status: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:card, status: "not-a-real-color") }
      .to raise_error(ArgumentError, /card/)
  end

  it "raises ArgumentError naming the offender and valid values for an unknown status_position" do
    expect { component_fragment(:card, status: "primary", status_position: "left") }
      .to raise_error(ArgumentError, /"left"/)
    expect { component_fragment(:card, status: "primary", status_position: "left") }
      .to raise_error(ArgumentError, /top, start, bottom/)
  end

  it_behaves_like "an element with an html hook", :card, { status: "primary" },
    hook: :status_html, selector: ".card-status-top"

  it "adds card-borderless for borderless: true" do
    fragment = component_fragment(:card, borderless: true)

    expect(fragment.css(".card").first["class"].split(/\s+/)).to include("card-borderless")
  end

  it "adds card-stacked for stacked: true" do
    fragment = component_fragment(:card, stacked: true)

    expect(fragment.css(".card").first["class"].split(/\s+/)).to include("card-stacked")
  end
end
