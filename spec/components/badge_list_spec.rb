# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::BadgeList", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:badge_list)

    expect(fragment.css(".badges-list")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :badge_list, {},
    hook: :html, selector: ".badges-list"

  it "appends a caller-supplied class instead of replacing badges-list" do
    fragment = component_fragment(:badge_list, html: { class: "mb-2" })
    element = fragment.css(".badges-list").first

    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("badges-list", "mb-2")
  end

  it "renders real badges passed through the body slot" do
    fragment = component_fragment(:badge_list) do |slots|
      slots.body do
        tabler_ui_view_context.tabler_ui.badge(text: "New") +
          tabler_ui_view_context.tabler_ui.badge(text: "Hot")
      end
    end

    badges = fragment.css(".badges-list > .badge")
    expect(badges.size).to eq(2)
    expect(badges.map { |b| b.text.strip }).to eq(%w[New Hot])
  end

  it "renders nothing inside when the body slot is omitted" do
    fragment = component_fragment(:badge_list)

    expect(fragment.css(".badges-list").first.text.strip).to eq("")
  end
end
