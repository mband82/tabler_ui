# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::CardGroup", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:card_group)

    expect(fragment.css(".card-group")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :card_group, {},
    hook: :html, selector: ".card-group"

  it "appends a caller-supplied class instead of replacing card-group" do
    fragment = component_fragment(:card_group, html: { class: "mb-4" })
    element = fragment.css(".card-group").first

    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("card-group", "mb-4")
  end

  it "renders real cards passed through the body slot" do
    fragment = component_fragment(:card_group) do |slots|
      slots.body do
        tabler_ui_view_context.tabler_ui.card(title: "One") { |card_slots| card_slots.body { "First" } } +
          tabler_ui_view_context.tabler_ui.card(title: "Two") { |card_slots| card_slots.body { "Second" } }
      end
    end

    cards = fragment.css(".card-group .card")
    expect(cards.size).to eq(2)
    expect(cards.map { |c| c.css(".card-title").text }).to eq(%w[One Two])
  end

  # Load-bearing part of the contract (see the class-level comment on
  # TablerUi::CardGroup::Component): .card-group > .card is a direct-child
  # selector, so the cards must be immediate children of the wrapper with no
  # intermediate element in between.
  it "renders the cards as direct children of .card-group" do
    fragment = component_fragment(:card_group) do |slots|
      slots.body do
        tabler_ui_view_context.tabler_ui.card(title: "One") { |card_slots| card_slots.body { "First" } } +
          tabler_ui_view_context.tabler_ui.card(title: "Two") { |card_slots| card_slots.body { "Second" } }
      end
    end

    direct_children = fragment.css(".card-group > .card")
    expect(direct_children.size).to eq(2)
  end

  it "renders nothing inside when the body slot is omitted" do
    fragment = component_fragment(:card_group)

    expect(fragment.css(".card-group").first.text.strip).to eq("")
  end
end
