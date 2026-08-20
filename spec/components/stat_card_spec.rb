# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::StatCard", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:stat_card)

    expect(fragment.css("div.card")).not_to be_empty
    expect(fragment.css("div.card-body")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :stat_card, {},
    hook: :html, selector: "div.card"

  it_behaves_like "an element with an html hook", :stat_card, {},
    hook: :body_html, selector: "div.card-body"

  it_behaves_like "an element with an html hook", :stat_card, {},
    hook: :value_html, selector: "div.h1"

  it_behaves_like "an element with an html hook", :stat_card, { url: "/details" },
    hook: :link_html, selector: "a.btn"

  it_behaves_like "an element with an html hook", :stat_card, { icon: "shopping-cart" },
    hook: :icon_html, selector: "span.avatar"

  it "appends a caller class to the root card's own class, not replacing it" do
    fragment = component_fragment(:stat_card, html: { class: "hook-extra-class" })
    classes = fragment.css("div.card").first["class"].split(/\s+/)

    expect(classes).to include("card", "hook-extra-class")
  end

  it "appends a caller class to the card-body's own class, not replacing it" do
    fragment = component_fragment(:stat_card, body_html: { class: "hook-extra-class" })
    classes = fragment.css("div.card-body").first["class"].split(/\s+/)

    expect(classes).to include("card-body", "hook-extra-class")
  end

  it "appends a caller class to the value element's own class, not replacing it" do
    fragment = component_fragment(:stat_card, value_html: { class: "hook-extra-class" })
    classes = fragment.css("div.h1").first["class"].split(/\s+/)

    expect(classes).to include("h1", "mb-0", "hook-extra-class")
  end

  it "appends a caller class to the Details link's own class, not replacing it" do
    fragment = component_fragment(:stat_card, url: "/details", link_html: { class: "hook-extra-class" })
    classes = fragment.css("a.btn").first["class"].split(/\s+/)

    expect(classes).to include("btn", "btn-sm", "btn-outline-primary", "hook-extra-class")
  end

  it "renders label:, value: and description: in the output" do
    fragment = component_fragment(:stat_card, label: "Sales", value: "456", description: "vs. last month")

    expect(fragment.css(".subheader").text).to eq("Sales")
    expect(fragment.css("div.h1").text).to eq("456")
    expect(fragment.css(".text-secondary.small").text).to eq("vs. last month")
  end

  it "renders a positive trend in green with an up arrow" do
    fragment = component_fragment(:stat_card, trend: 12)
    trend = fragment.css("span.text-green").first

    expect(trend).not_to be_nil
    expect(trend.text).to include("+12%")

    svg = trend.css("svg").first
    expect(svg["class"]).to include("icon-tabler-trending-up")
    expect(svg["class"]).not_to include("icon-tabler-bug")
  end

  it "renders a negative trend in red with a down arrow" do
    fragment = component_fragment(:stat_card, trend: -8)
    trend = fragment.css("span.text-red").first

    expect(trend).not_to be_nil
    expect(trend.text).to include("-8%")

    svg = trend.css("svg").first
    expect(svg["class"]).to include("icon-tabler-trending-down")
    expect(svg["class"]).not_to include("icon-tabler-bug")
  end

  it "renders no trend indicator when trend: is zero" do
    fragment = component_fragment(:stat_card, trend: 0)

    expect(fragment.css("span.text-green")).to be_empty
    expect(fragment.css("span.text-red")).to be_empty
  end

  it "renders no trend indicator when trend: is nil" do
    fragment = component_fragment(:stat_card)

    expect(fragment.css("span.text-green")).to be_empty
    expect(fragment.css("span.text-red")).to be_empty
  end

  it "renders the named icon via the dispatcher, not the error-fallback bug icon" do
    fragment = component_fragment(:stat_card, icon: "shopping-cart")
    svg = fragment.css("span.avatar svg").first

    expect(svg).not_to be_nil
    expect(svg["class"]).to include("icon-tabler-shopping-cart")
    expect(svg["class"]).not_to include("icon-tabler-bug")
  end

  it "renders no icon badge when icon: is omitted" do
    fragment = component_fragment(:stat_card)

    expect(fragment.css("span.avatar")).to be_empty
  end

  it "renders the icon badge with the avatar class, not the icon-box class that " \
     "matched no CSS and left the badge with no size or centring (the reported bug)" do
    fragment = component_fragment(:stat_card, icon: "shopping-cart")
    badge = fragment.css("span.avatar").first

    expect(badge).not_to be_nil
    classes = badge["class"].split(/\s+/)
    expect(classes).not_to include("icon-box")
  end

  it "keeps the icon badge's background colour class alongside the avatar class" do
    fragment = component_fragment(:stat_card, icon: "shopping-cart", color: "green")
    badge = fragment.css("span.avatar").first
    classes = badge["class"].split(/\s+/)

    expect(classes).to include("avatar", "bg-green-lt")
  end

  it "renders a Details link when url: is given" do
    fragment = component_fragment(:stat_card, url: "/clients")
    link = fragment.css("a.btn").first

    expect(link).not_to be_nil
    expect(link["href"]).to eq("/clients")
    expect(link.text).to eq("Details")
  end

  it "does not render a Details link when url: is omitted" do
    fragment = component_fragment(:stat_card)

    expect(fragment.css("a.btn")).to be_empty
  end

  it "raises ArgumentError naming stat_card for an unknown color" do
    expect { component_fragment(:stat_card, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:stat_card, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /stat_card/)
  end
end
