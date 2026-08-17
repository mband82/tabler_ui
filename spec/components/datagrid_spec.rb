# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Datagrid", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:datagrid)

    expect(fragment.css(".datagrid")).to be_empty
    expect(fragment.to_html.strip).to eq("")
  end

  it "yields the component itself in builder style" do
    yielded = nil

    component_fragment(:datagrid) do |dg|
      yielded = dg
    end

    expect(TablerUi::Datagrid::Component.builder_style?).to be true
    expect(yielded).to respond_to(:item)
  end

  it "renders items added via the builder, with title and content" do
    fragment = component_fragment(:datagrid) do |dg|
      dg.item "Name", content: "Ada Lovelace"
    end

    expect(fragment.css(".datagrid-title").first.text).to eq("Name")
    expect(fragment.css(".datagrid-content").first.text.strip).to eq("Ada Lovelace")
  end

  it "renders content supplied via options[:content]" do
    fragment = component_fragment(:datagrid) do |dg|
      dg.item "Name", content: "Ada"
    end

    expect(fragment.css(".datagrid-content").first.text.strip).to eq("Ada")
  end

  it "renders content supplied via a block" do
    fragment = component_fragment(:datagrid) do |dg|
      dg.item "Bio" do
        "Mathematician"
      end
    end

    expect(fragment.css(".datagrid-content").first.text.strip).to eq("Mathematician")
  end

  it "prefers the block over options[:content] when both are given" do
    fragment = component_fragment(:datagrid) do |dg|
      dg.item "Name", content: "from option" do
        "from block"
      end
    end

    text = fragment.css(".datagrid-content").first.text.strip
    expect(text).to eq("from block")
    expect(text).not_to include("from option")
  end

  it_behaves_like "an element with an html hook", :datagrid, { items: [{ title: "Name", content: "Ada" }] },
    hook: :html, selector: ".datagrid"

  it "applies item_html: as a plain Hash to every item" do
    fragment = component_fragment(
      :datagrid,
      items: [{ title: "Name", content: "Ada" }, { title: "Bio", content: "Mathematician" }],
      item_html: { class: "all-items" }
    )
    items = fragment.css(".datagrid-item")

    expect(items.size).to eq(2)
    items.each { |item| expect(item["class"].to_s.split(/\s+/)).to include("all-items") }
  end

  it "applies item_html: as a callable, so items can differ" do
    fragment = component_fragment(
      :datagrid,
      items: [{ title: "Name", content: "Ada" }, { title: "Bio", content: "Mathematician" }],
      item_html: ->(item) { item[:title] == "Name" ? { class: "highlight" } : {} }
    )
    items = fragment.css(".datagrid-item")

    expect(items[0]["class"].to_s.split(/\s+/)).to include("highlight")
    expect(items[1]["class"].to_s).not_to include("highlight")
  end

  it "applies title_html: per item" do
    fragment = component_fragment(
      :datagrid,
      items: [{ title: "Name", content: "Ada" }, { title: "Bio", content: "Mathematician" }],
      title_html: ->(item) { item[:title] == "Name" ? { class: "highlight-title" } : {} }
    )
    titles = fragment.css(".datagrid-title")

    expect(titles[0]["class"].to_s.split(/\s+/)).to include("highlight-title")
    expect(titles[1]["class"].to_s).not_to include("highlight-title")
  end

  it "applies content_html: per item" do
    fragment = component_fragment(
      :datagrid,
      items: [{ title: "Name", content: "Ada" }, { title: "Bio", content: "Mathematician" }],
      content_html: ->(item) { item[:title] == "Name" ? { class: "highlight-content" } : {} }
    )
    contents = fragment.css(".datagrid-content")

    expect(contents[0]["class"].to_s.split(/\s+/)).to include("highlight-content")
    expect(contents[1]["class"].to_s).not_to include("highlight-content")
  end

  it "renders items: passed directly at construction alongside the builder" do
    fragment = component_fragment(:datagrid, items: [{ title: "Preset", content: "value" }]) do |dg|
      dg.item "Added", content: "later"
    end

    titles = fragment.css(".datagrid-title").map(&:text)
    expect(titles).to eq(%w[Preset Added])
  end
end
