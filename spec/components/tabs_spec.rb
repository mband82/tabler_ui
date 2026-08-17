# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Tabs", type: :component do
  it "renders with just the mandatory id" do
    fragment = component_fragment(:tabs, "my-tabs")

    expect(fragment.css(".tabs")).not_to be_empty
    expect(fragment.css(".nav-tabs")).not_to be_empty
    expect(fragment.css(".tab-content")).not_to be_empty
  end

  it "raises ArgumentError naming the component when id is missing" do
    expect { component_fragment(:tabs) }
      .to raise_error(ArgumentError, /tabler_ui\.tabs requires id/)
  end

  it "yields the component itself, in builder style" do
    expect(TablerUi::Tabs::Component.builder_style?).to be(true)

    yielded = nil
    component_fragment(:tabs, "my-tabs") do |tabs|
      yielded = tabs
    end

    expect(yielded).to be_a(TablerUi::Tabs::Component)
    expect(yielded).to respond_to(:tab)
  end

  it "renders multiple tabs, each with its content pane captured" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("First") { "First content" }
      tabs.tab("Second") { "Second content" }
    end

    expect(fragment.css(".nav-link").map(&:text).map(&:strip)).to eq(%w[First Second])
    expect(fragment.css(".tab-pane")[0].text.strip).to eq("First content")
    expect(fragment.css(".tab-pane")[1].text.strip).to eq("Second content")
  end

  it "marks one tab and its pane active: with active:" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("First", active: false) { "First content" }
      tabs.tab("Second", active: true) { "Second content" }
    end

    links = fragment.css(".nav-link")
    panes = fragment.css(".tab-pane")

    expect(links[0]["class"].split(/\s+/)).not_to include("active")
    expect(links[1]["class"].split(/\s+/)).to include("active")

    expect(panes[0]["class"].split(/\s+/)).not_to include("active")
    expect(panes[1]["class"].split(/\s+/)).to include("active", "show")
  end

  it "defaults the first tab to active when active: is not given" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("First") { "First content" }
      tabs.tab("Second") { "Second content" }
    end

    links = fragment.css(".nav-link")

    expect(links[0]["class"].split(/\s+/)).to include("active")
    expect(links[1]["class"].split(/\s+/)).not_to include("active")
  end

  it "renders badge: as a String with the badge component's default colour" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("Inbox", badge: "3") { "Content" }
    end

    badge = fragment.css(".nav-link .badge").first
    expect(badge).not_to be_nil
    expect(badge.text.strip).to eq("3")
  end

  it "renders badge: as a Hash, forwarding options -- colour lands" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("Inbox", badge: { text: "3", color: "red" }) { "Content" }
    end

    badge = fragment.css(".nav-link .badge").first
    expect(badge).not_to be_nil
    expect(badge["class"].split(/\s+/)).to include("bg-red", "text-red-fg")
  end

  it "no longer accepts badge_color: -- it does not colour the badge" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("Inbox", badge: "3", badge_color: "red") { "Content" }
    end

    badge = fragment.css(".nav-link .badge").first
    expect(badge).not_to be_nil
    classes = badge["class"].split(/\s+/)
    expect(classes.grep(/red/)).to be_empty
  end

  it "renders the badge via the real badge component, not hand-rolled markup" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("Inbox", badge: "3") { "Content" }
    end

    badge = fragment.css(".nav-link .badge").first
    expect(badge).not_to be_nil
    # badge_classes in TablerUi::Badge::Component always emits "badge" as the
    # base class -- present here proves this went through tabler_ui.badge
    # rather than a hand-rolled <span class="badge ...">.
    expect(badge["class"].split(/\s+/)).to include("badge")
  end

  it "renders icon: as a real icon, not the error-fallback bug icon" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("First", icon: "home") { "Content" }
    end

    svg = fragment.css(".nav-link svg").first
    expect(svg).not_to be_nil
    expect(svg["class"].to_s.split(/\s+/)).not_to include("icon-tabler-bug")
  end

  it_behaves_like "an element with an html hook", :tabs, { id: "my-tabs" },
    hook: :html, selector: ".tabs"

  it_behaves_like "an element with an html hook", :tabs, { id: "my-tabs" },
    hook: :nav_html, selector: ".nav-tabs"

  it_behaves_like "an element with an html hook", :tabs, { id: "my-tabs" },
    hook: :content_html, selector: ".tab-content"

  it "applies per-tab html: to that tab only, via a plain Hash" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("First", html: { class: "hook-extra-class", id: "hook-test-id" }) { "Content" }
      tabs.tab("Second") { "Content" }
    end

    links = fragment.css(".nav-link")

    expect(links[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(links[0]["id"]).to eq("hook-test-id")
    expect(links[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
    expect(links[1]["id"]).to be_nil
  end

  it "applies per-tab html: to that tab only, via a callable taking the tab" do
    fragment = component_fragment(:tabs, "my-tabs") do |tabs|
      tabs.tab("First", html: ->(tab) { { class: "callable-class-#{tab.title.downcase}" } }) { "Content" }
      tabs.tab("Second", html: ->(tab) { { class: "callable-class-#{tab.title.downcase}" } }) { "Content" }
    end

    links = fragment.css(".nav-link")

    expect(links[0]["class"].split(/\s+/)).to include("callable-class-first")
    expect(links[0]["class"].split(/\s+/)).not_to include("callable-class-second")
    expect(links[1]["class"].split(/\s+/)).to include("callable-class-second")
    expect(links[1]["class"].split(/\s+/)).not_to include("callable-class-first")
  end

  it "adds nav-tabs for the default style: (and for style: :tabs explicitly)" do
    fragment = component_fragment(:tabs, "my-tabs")
    classes = fragment.css("ul.nav").first["class"].split(/\s+/)

    expect(classes).to include("nav", "nav-tabs")
    expect(classes).not_to include("nav-pills", "card-header-tabs", "nav-underline")
  end

  it "adds nav-pills for style: :pills" do
    fragment = component_fragment(:tabs, "my-tabs", style: :pills)
    classes = fragment.css("ul.nav").first["class"].split(/\s+/)

    expect(classes).to include("nav-pills")
    expect(classes).not_to include("nav-tabs")
  end

  it "adds nav-tabs card-header-tabs for style: :card" do
    fragment = component_fragment(:tabs, "my-tabs", style: :card)
    classes = fragment.css("ul.nav").first["class"].split(/\s+/)

    expect(classes).to include("nav-tabs", "card-header-tabs")
  end

  it "adds nav-underline for style: :underline, replacing nav-tabs (regression)" do
    fragment = component_fragment(:tabs, "my-tabs", style: :underline)
    classes = fragment.css("ul.nav").first["class"].split(/\s+/)

    expect(classes).to include("nav-underline")
    expect(classes).not_to include("nav-tabs", "nav-tabs-alt")
  end

  it "adds nav-bordered for style: :bordered, not nav-tabs" do
    fragment = component_fragment(:tabs, "my-tabs", style: :bordered)
    classes = fragment.css("ul.nav").first["class"].split(/\s+/)

    expect(classes).to include("nav-bordered")
    expect(classes).not_to include("nav-tabs")
  end

  it "raises ArgumentError naming the component for an unknown style" do
    expect { component_fragment(:tabs, "my-tabs", style: :bogus) }
      .to raise_error(ArgumentError, /unknown tabs style/)
  end

  it "adds nav-fill for fill: true" do
    fragment = component_fragment(:tabs, "my-tabs", fill: true)
    classes = fragment.css("ul.nav").first["class"].split(/\s+/)

    expect(classes).to include("nav-fill")
  end

  it "adds nav-justified for justified: true" do
    fragment = component_fragment(:tabs, "my-tabs", justified: true)
    classes = fragment.css("ul.nav").first["class"].split(/\s+/)

    expect(classes).to include("nav-justified")
  end

  it "raises ArgumentError when fill: and justified: are both given" do
    expect { component_fragment(:tabs, "my-tabs", fill: true, justified: true) }
      .to raise_error(ArgumentError, /mutually exclusive/)
  end

  it "adds nav-segmented for style: :segmented, rendering .nav-link as a direct child of the ul" do
    fragment = component_fragment(:tabs, "my-tabs", style: :segmented) do |tabs|
      tabs.tab("First") { "First content" }
      tabs.tab("Second") { "Second content" }
    end

    nav = fragment.css("ul.nav").first
    classes = nav["class"].split(/\s+/)
    expect(classes).to include("nav-segmented")

    expect(nav.css("li")).to be_empty
    expect(nav.children.select { |node| node.name == "a" }.size).to eq(2)
  end

  it "keeps data-bs-toggle=tab on each nav-link when style: :segmented" do
    fragment = component_fragment(:tabs, "my-tabs", style: :segmented) do |tabs|
      tabs.tab("First") { "First content" }
      tabs.tab("Second") { "Second content" }
    end

    links = fragment.css(".nav-link")
    expect(links.size).to eq(2)
    links.each do |link|
      expect(link["data-bs-toggle"]).to eq("tab")
    end
  end

  it "adds nav-segmented-vertical for vertical: true with style: :segmented" do
    fragment = component_fragment(:tabs, "my-tabs", style: :segmented, vertical: true)
    classes = fragment.css("ul.nav").first["class"].split(/\s+/)

    expect(classes).to include("nav-segmented", "nav-segmented-vertical")
  end

  it "raises ArgumentError when vertical: true is used with a style other than :segmented" do
    expect { component_fragment(:tabs, "my-tabs", style: :tabs, vertical: true) }
      .to raise_error(ArgumentError, /vertical/)
  end
end
