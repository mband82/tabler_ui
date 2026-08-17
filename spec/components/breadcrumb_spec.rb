# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Breadcrumb", type: :component do
  it "renders with no arguments and no items, without raising" do
    fragment = component_fragment(:breadcrumb)

    expect(fragment.css("nav")).not_to be_empty
    expect(fragment.css("ol.breadcrumb")).not_to be_empty
    expect(fragment.css("li.breadcrumb-item")).to be_empty
  end

  it "yields the component itself, in builder style" do
    expect(TablerUi::Breadcrumb::Component.builder_style?).to be(true)

    yielded = nil
    component_fragment(:breadcrumb) do |breadcrumb|
      yielded = breadcrumb
    end

    expect(yielded).to be_a(TablerUi::Breadcrumb::Component)
    expect(yielded).to respond_to(:item)
  end

  it "renders items in order" do
    fragment = component_fragment(:breadcrumb) do |breadcrumb|
      breadcrumb.item("Home", url: "/")
      breadcrumb.item("Library", url: "/library")
      breadcrumb.item("Data")
    end

    expect(fragment.css("li.breadcrumb-item").map(&:text).map(&:strip)).to eq(%w[Home Library Data])
  end

  it "url: renders a link" do
    fragment = component_fragment(:breadcrumb) do |breadcrumb|
      breadcrumb.item("Home", url: "/")
      breadcrumb.item("Library", url: "/library")
      breadcrumb.item("Data")
    end

    home = fragment.css("li.breadcrumb-item")[0]
    expect(home.css("a").first["href"]).to eq("/")
  end

  it "absence of url: renders plain text, not a link" do
    fragment = component_fragment(:breadcrumb) do |breadcrumb|
      breadcrumb.item("Home", url: "/")
      breadcrumb.item("Library", url: "/library")
      breadcrumb.item("Data")
    end

    data = fragment.css("li.breadcrumb-item")[2]
    expect(data.css("a")).to be_empty
    expect(data.text.strip).to eq("Data")
  end

  it "with no item explicitly marked active:, the last item is treated as current" do
    fragment = component_fragment(:breadcrumb) do |breadcrumb|
      breadcrumb.item("Home", url: "/")
      breadcrumb.item("Library", url: "/library")
      breadcrumb.item("Data")
    end

    items = fragment.css("li.breadcrumb-item")
    expect(items.last["class"].split(/\s+/)).to include("active")
    expect(items.first["class"].split(/\s+/)).not_to include("active")
  end

  it "active: marks the current item and it renders without a link, even with a url:" do
    fragment = component_fragment(:breadcrumb) do |breadcrumb|
      breadcrumb.item("Home", url: "/")
      breadcrumb.item("Reports", url: "/reports", active: true)
      breadcrumb.item("2024", url: "/reports/2024")
    end

    items = fragment.css("li.breadcrumb-item")

    reports = items[1]
    expect(reports["class"].split(/\s+/)).to include("active")
    expect(reports.css("a")).to be_empty
    expect(reports.text.strip).to eq("Reports")

    # An explicit active: elsewhere switches off the automatic last-item
    # default -- the last item goes back to being a normal link.
    last = items[2]
    expect(last["class"].split(/\s+/)).not_to include("active")
    expect(last.css("a").first["href"]).to eq("/reports/2024")
  end

  it "raises a helpful error when item is called the old keyword way" do
    expect {
      component_fragment(:breadcrumb) { |breadcrumb| breadcrumb.item(title: "Home") }
    }.to raise_error(ArgumentError, /breadcrumb#item takes title positionally/)
  end

  it "style: :dots produces breadcrumb-dots" do
    fragment = component_fragment(:breadcrumb, style: :dots)

    expect(fragment.css("ol.breadcrumb").first["class"].split(/\s+/)).to include("breadcrumb-dots")
  end

  it "style: :arrows produces breadcrumb-arrows" do
    fragment = component_fragment(:breadcrumb, style: :arrows)

    expect(fragment.css("ol.breadcrumb").first["class"].split(/\s+/)).to include("breadcrumb-arrows")
  end

  it "style: :bullets produces breadcrumb-bullets" do
    fragment = component_fragment(:breadcrumb, style: :bullets)

    expect(fragment.css("ol.breadcrumb").first["class"].split(/\s+/)).to include("breadcrumb-bullets")
  end

  it "no style: produces no divider modifier class" do
    fragment = component_fragment(:breadcrumb)
    classes = fragment.css("ol.breadcrumb").first["class"].split(/\s+/)

    expect(classes).not_to include("breadcrumb-dots", "breadcrumb-arrows", "breadcrumb-bullets")
  end

  it "raises ArgumentError naming the component on an unknown style" do
    expect { component_fragment(:breadcrumb, style: :dashes) }
      .to raise_error(ArgumentError, /unknown breadcrumb style.*dashes/)
  end

  it "muted: produces breadcrumb-muted" do
    fragment = component_fragment(:breadcrumb, muted: true)

    expect(fragment.css("ol.breadcrumb").first["class"].split(/\s+/)).to include("breadcrumb-muted")
  end

  it "muted: false does not produce breadcrumb-muted" do
    fragment = component_fragment(:breadcrumb, muted: false)

    expect(fragment.css("ol.breadcrumb").first["class"].split(/\s+/)).not_to include("breadcrumb-muted")
  end

  it_behaves_like "an element with an html hook", :breadcrumb, {},
    hook: :html, selector: "ol.breadcrumb"

  it "applies per-item html: to that item only, via a plain Hash" do
    fragment = component_fragment(:breadcrumb) do |breadcrumb|
      breadcrumb.item("First", url: "/first", html: { class: "hook-extra-class", id: "hook-test-id" })
      breadcrumb.item("Second", url: "/second")
    end

    items = fragment.css("li.breadcrumb-item")

    expect(items[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(items[0]["id"]).to eq("hook-test-id")
    expect(items[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
    expect(items[1]["id"]).to be_nil
  end

  it "applies per-item html: to that item only, via a callable taking the item" do
    fragment = component_fragment(:breadcrumb) do |breadcrumb|
      breadcrumb.item("First", url: "/first", html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
      breadcrumb.item("Second", url: "/second",
                                 html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
    end

    items = fragment.css("li.breadcrumb-item")

    expect(items[0]["class"].split(/\s+/)).to include("callable-class-first")
    expect(items[0]["class"].split(/\s+/)).not_to include("callable-class-second")
    expect(items[1]["class"].split(/\s+/)).to include("callable-class-second")
    expect(items[1]["class"].split(/\s+/)).not_to include("callable-class-first")
  end

  describe "accessibility markup" do
    it "wraps the list in a nav landmark with a translated aria-label" do
      fragment = component_fragment(:breadcrumb)

      nav = fragment.css("nav").first
      expect(nav).not_to be_nil
      expect(nav["aria-label"]).to eq(I18n.t("tabler_ui.breadcrumb.aria_label"))
      expect(nav.css("ol.breadcrumb")).not_to be_empty
    end

    it "gives the current item aria-current=\"page\"" do
      fragment = component_fragment(:breadcrumb) do |breadcrumb|
        breadcrumb.item("Home", url: "/")
        breadcrumb.item("Data")
      end

      items = fragment.css("li.breadcrumb-item")
      expect(items[0]["aria-current"]).to be_nil
      expect(items[1]["aria-current"]).to eq("page")
    end
  end
end
