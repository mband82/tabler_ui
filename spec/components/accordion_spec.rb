# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Accordion", type: :component do
  it "renders with just the mandatory id" do
    fragment = component_fragment(:accordion, "my-accordion")

    expect(fragment.css(".accordion")).not_to be_empty
    expect(fragment.css(".accordion")[0]["id"]).to eq("my-accordion")
  end

  it "raises ArgumentError naming the component when id is missing" do
    expect { component_fragment(:accordion) }
      .to raise_error(ArgumentError, /tabler_ui\.accordion requires id/)
  end

  it "yields the component itself, in builder style" do
    expect(TablerUi::Accordion::Component.builder_style?).to be(true)

    yielded = nil
    component_fragment(:accordion, "my-accordion") do |accordion|
      yielded = accordion
    end

    expect(yielded).to be_a(TablerUi::Accordion::Component)
    expect(yielded).to respond_to(:item)
  end

  it "raises when item is called the old keyword way" do
    expect {
      component_fragment(:accordion, "my-accordion") do |accordion|
        accordion.item(title: "First")
      end
    }.to raise_error(ArgumentError, /accordion#item takes title positionally/)
  end

  it "renders multiple items, each with a unique id-linked header/panel pair" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First") { "First content" }
      accordion.item("Second") { "Second content" }
    end

    headers = fragment.css(".accordion-header")
    buttons = fragment.css(".accordion-button")
    panels = fragment.css(".accordion-collapse")

    expect(buttons.map(&:text).map(&:strip)).to eq(%w[First Second])
    expect(panels[0].css(".accordion-body").text.strip).to eq("First content")
    expect(panels[1].css(".accordion-body").text.strip).to eq("Second content")

    ids = panels.map { |p| p["id"] }
    expect(ids.uniq.length).to eq(2)
    expect(headers.map { |h| h["id"] }.uniq.length).to eq(2)
  end

  it "defaults to no item open when none are marked open:" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First") { "Content" }
      accordion.item("Second") { "Content" }
    end

    buttons = fragment.css(".accordion-button")
    panels = fragment.css(".accordion-collapse")

    expect(buttons.map { |b| b["class"].split(/\s+/) }).to all(include("collapsed"))
    expect(panels.map { |p| p["class"].split(/\s+/) }).to all(satisfy { |c| !c.include?("show") })
    expect(buttons.map { |b| b["aria-expanded"] }).to eq(%w[false false])
  end

  it "marks one item and its pane expanded with open:" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", open: false) { "Content" }
      accordion.item("Second", open: true) { "Content" }
    end

    buttons = fragment.css(".accordion-button")
    panels = fragment.css(".accordion-collapse")

    expect(buttons[0]["class"].split(/\s+/)).to include("collapsed")
    expect(buttons[0]["aria-expanded"]).to eq("false")
    expect(buttons[1]["class"].split(/\s+/)).not_to include("collapsed")
    expect(buttons[1]["aria-expanded"]).to eq("true")

    expect(panels[0]["class"].split(/\s+/)).not_to include("show")
    expect(panels[1]["class"].split(/\s+/)).to include("show")
  end

  it "emits data-bs-parent for single-open (the default)" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", open: true) { "Content" }
      accordion.item("Second") { "Content" }
    end

    panels = fragment.css(".accordion-collapse")
    expect(panels.map { |p| p["data-bs-parent"] }).to eq(["#my-accordion", "#my-accordion"])
  end

  it "omits data-bs-parent when multiple: true, so several panes can stay open" do
    fragment = component_fragment(:accordion, "my-accordion", multiple: true) do |accordion|
      accordion.item("First", open: true) { "Content" }
      accordion.item("Second", open: true) { "Content" }
    end

    panels = fragment.css(".accordion-collapse")
    expect(panels.map { |p| p["data-bs-parent"] }).to eq([nil, nil])
    expect(panels.map { |p| p["class"].split(/\s+/) }).to all(include("show"))
  end

  it "raises when more than one item is marked open: without multiple: true" do
    expect {
      component_fragment(:accordion, "my-accordion") do |accordion|
        accordion.item("First", open: true) { "Content" }
        accordion.item("Second", open: true) { "Content" }
      end
    }.to raise_error(ArgumentError, /my-accordion.*2 items marked open.*multiple: true/)
  end

  it "adds accordion-flush for flush:" do
    fragment = component_fragment(:accordion, "my-accordion", flush: true)
    expect(fragment.css(".accordion")[0]["class"].split(/\s+/)).to include("accordion-flush")
  end

  it "adds accordion-inverted for inverted:" do
    fragment = component_fragment(:accordion, "my-accordion", inverted: true)
    expect(fragment.css(".accordion")[0]["class"].split(/\s+/)).to include("accordion-inverted")
  end

  it "adds accordion-tabs for style: :tabs" do
    fragment = component_fragment(:accordion, "my-accordion", style: :tabs)
    expect(fragment.css(".accordion")[0]["class"].split(/\s+/)).to include("accordion-tabs")
  end

  it "does not add accordion-tabs for the default style" do
    fragment = component_fragment(:accordion, "my-accordion")
    expect(fragment.css(".accordion")[0]["class"].split(/\s+/)).not_to include("accordion-tabs")
  end

  it "renders a chevron toggle icon by default" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First") { "Content" }
    end

    toggle = fragment.css(".accordion-button-toggle").first
    expect(toggle).not_to be_nil
    expect(toggle["class"].split(/\s+/)).not_to include("accordion-button-toggle-plus")
    expect(toggle["class"].to_s).to include("icon-tabler-chevron-down")
  end

  it "renders a plus toggle icon for toggle_style: :plus" do
    fragment = component_fragment(:accordion, "my-accordion", toggle_style: :plus) do |accordion|
      accordion.item("First") { "Content" }
    end

    toggle = fragment.css(".accordion-button-toggle").first
    expect(toggle).not_to be_nil
    expect(toggle["class"].split(/\s+/)).to include("accordion-button-toggle-plus")
    expect(toggle["class"].to_s).to include("icon-tabler-plus")
  end

  it "renders icon: as a real icon, not the error-fallback bug icon" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", icon: "home") { "Content" }
    end

    svgs = fragment.css(".accordion-button svg")
    expect(svgs).not_to be_empty
    expect(svgs.map { |s| s["class"].to_s }.join).to include("icon-tabler-home")
    expect(svgs.map { |s| s["class"].to_s }.join).not_to include("icon-tabler-bug")
  end

  it "sets data-controller=\"tabler-ui--collapse\" on each panel" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First") { "Content" }
      accordion.item("Second") { "Content" }
    end

    panels = fragment.css(".accordion-collapse")
    expect(panels).not_to be_empty
    expect(panels.map { |p| p["data-controller"] }).to all(eq("tabler-ui--collapse"))
  end

  it "wires aria-expanded, aria-controls and aria-labelledby to real ids" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", open: true) { "Content" }
      accordion.item("Second") { "Content" }
    end

    buttons = fragment.css(".accordion-button")
    panels = fragment.css(".accordion-collapse")
    headers = fragment.css(".accordion-header")

    buttons.each_with_index do |button, i|
      panel = panels[i]
      header = headers[i]

      expect(button["aria-expanded"]).to eq(i.zero? ? "true" : "false")
      expect(button["aria-controls"]).to eq(panel["id"])
      expect(panel["aria-labelledby"]).to eq(header["id"])
    end
  end

  it_behaves_like "an element with an html hook", :accordion, { id: "my-accordion" },
    hook: :html, selector: ".accordion"

  it "applies per-item html: to that item's .accordion-button only, via a plain Hash" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", html: { class: "hook-extra-class", id: "hook-test-id" }) { "Content" }
      accordion.item("Second") { "Content" }
    end

    buttons = fragment.css(".accordion-button")

    expect(buttons[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(buttons[0]["id"]).to eq("hook-test-id")
    expect(buttons[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
    expect(buttons[1]["id"]).to be_nil
  end

  it "applies per-item html: to that item's .accordion-button only, via a callable taking the item" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }) { "Content" }
      accordion.item("Second", html: ->(item) { { class: "callable-class-#{item.title.downcase}" } }) { "Content" }
    end

    buttons = fragment.css(".accordion-button")

    expect(buttons[0]["class"].split(/\s+/)).to include("callable-class-first")
    expect(buttons[0]["class"].split(/\s+/)).not_to include("callable-class-second")
    expect(buttons[1]["class"].split(/\s+/)).to include("callable-class-second")
    expect(buttons[1]["class"].split(/\s+/)).not_to include("callable-class-first")
  end

  it "applies per-item header_html: to that item's .accordion-header only, via a plain Hash" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", header_html: { class: "hook-extra-class" }) { "Content" }
      accordion.item("Second") { "Content" }
    end

    headers = fragment.css(".accordion-header")

    expect(headers[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(headers[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
  end

  it "applies per-item header_html: via a callable taking the item" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", header_html: ->(item) { { class: "callable-#{item.title.downcase}" } }) { "Content" }
      accordion.item("Second") { "Content" }
    end

    headers = fragment.css(".accordion-header")

    expect(headers[0]["class"].split(/\s+/)).to include("callable-first")
    expect(headers[1]["class"].split(/\s+/)).not_to include("callable-first")
  end

  it "applies per-item body_html: to that item's .accordion-body only, via a plain Hash" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", body_html: { class: "hook-extra-class" }) { "Content" }
      accordion.item("Second") { "Content" }
    end

    bodies = fragment.css(".accordion-body")

    expect(bodies[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(bodies[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
  end

  it "applies per-item body_html: via a callable taking the item" do
    fragment = component_fragment(:accordion, "my-accordion") do |accordion|
      accordion.item("First", body_html: ->(item) { { class: "callable-#{item.title.downcase}" } }) { "Content" }
      accordion.item("Second") { "Content" }
    end

    bodies = fragment.css(".accordion-body")

    expect(bodies[0]["class"].split(/\s+/)).to include("callable-first")
    expect(bodies[1]["class"].split(/\s+/)).not_to include("callable-first")
  end
end
