# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::PageHeader", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:page_header)

    expect(fragment.css(".page-header")).not_to be_empty
    expect(fragment.css("h2.page-title")).not_to be_empty
    expect(fragment.css(".page-pretitle")).to be_empty
  end

  it "renders title: in an h2.page-title" do
    fragment = component_fragment(:page_header, title: "Dashboard")

    expect(fragment.css("h2.page-title").text).to eq("Dashboard")
  end

  it "renders pretitle: in .page-pretitle" do
    fragment = component_fragment(:page_header, title: "Dashboard", pretitle: "Overview")

    expect(fragment.css(".page-pretitle").text).to eq("Overview")
  end

  it "renders no pretitle element when pretitle: is omitted" do
    fragment = component_fragment(:page_header, title: "Dashboard")

    expect(fragment.css(".page-pretitle")).to be_empty
  end

  it "renders subtitle: in .page-subtitle, after the title and separate from pretitle" do
    fragment = component_fragment(:page_header, title: "Dashboard", subtitle: "Last 30 days")

    expect(fragment.css(".page-subtitle").text).to eq("Last 30 days")
    expect(fragment.css(".page-pretitle")).to be_empty
  end

  it "renders no subtitle element when subtitle: is omitted" do
    fragment = component_fragment(:page_header, title: "Dashboard")

    expect(fragment.css(".page-subtitle")).to be_empty
  end

  it "positions .page-subtitle immediately after h2.page-title, inside the same .col" do
    fragment = component_fragment(:page_header, title: "Dashboard", subtitle: "Last 30 days")
    col = fragment.css(".col").first
    children = col.css("> *")

    expect(children.map(&:name)).to eq(%w[h2 div])
    expect(children.last["class"].to_s.split(/\s+/)).to include("page-subtitle")
  end

  it "renders pretitle before the title and subtitle after it when both are present" do
    fragment = component_fragment(:page_header, title: "Dashboard", pretitle: "Overview", subtitle: "Last 30 days")
    col = fragment.css(".col").first
    children = col.css("> *")

    expect(children.map { |el| el["class"] }).to eq(%w[page-pretitle page-title page-subtitle])
  end

  it "appends page-header-border to the root when border: true" do
    fragment = component_fragment(:page_header, title: "Dashboard", border: true)
    element = fragment.css(".page-header").first

    expect(element["class"].to_s.split(/\s+/)).to include("page-header-border")
  end

  it "does not add page-header-border by default" do
    fragment = component_fragment(:page_header, title: "Dashboard")
    element = fragment.css(".page-header").first

    expect(element["class"].to_s.split(/\s+/)).not_to include("page-header-border")
  end

  it "appends page-title-lg alongside page-title when title_size: 'lg'" do
    fragment = component_fragment(:page_header, title: "Dashboard", title_size: "lg")
    element = fragment.css("h2.page-title").first

    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("page-title")
    expect(classes).to include("page-title-lg")
  end

  it "raises ArgumentError for an invalid title_size:" do
    expect do
      component_fragment(:page_header, title: "Dashboard", title_size: "xl")
    end.to raise_error(ArgumentError, /xl/)
  end

  it "leaves existing output unchanged when none of the new options are passed" do
    fragment = component_fragment(:page_header, title: "Dashboard", pretitle: "Overview")
    element = fragment.css(".page-header").first
    title = fragment.css("h2.page-title").first

    expect(element["class"].to_s.split(/\s+/)).to eq(%w[page-header d-print-none mb-3])
    expect(title["class"].to_s.split(/\s+/)).to eq(%w[page-title])
    expect(fragment.css(".page-subtitle")).to be_empty
  end

  it_behaves_like "an element with an html hook", :page_header, {},
    hook: :html, selector: ".page-header"

  it_behaves_like "an element with an html hook", :page_header, { title: "Dashboard" },
    hook: :title_html, selector: ".page-title"

  it_behaves_like "an element with an html hook", :page_header, { title: "Dashboard", pretitle: "Overview" },
    hook: :pretitle_html, selector: ".page-pretitle"

  it_behaves_like "an element with an html hook", :page_header, { title: "Dashboard", subtitle: "Last 30 days" },
    hook: :subtitle_html, selector: ".page-subtitle"

  it "passes id/data/class through buttons_html: onto the buttons column" do
    fragment = component_fragment(:page_header, title: "Dashboard",
                                                  buttons_html: { class: "hook-extra-class", id: "hook-test-id",
                                                                   data: { testid: "hook-test-data" } }) do |slots|
      slots.buttons { "Action" }
    end
    element = fragment.css(".col-auto").first

    expect(element).not_to be_nil
    expect(element["class"].to_s.split(/\s+/)).to include("hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it "appends a caller-supplied class on buttons_html: instead of replacing the component's own" do
    fragment = component_fragment(:page_header, title: "Dashboard",
                                                  buttons_html: { class: "hook-extra-class" }) do |slots|
      slots.buttons { "Action" }
    end
    element = fragment.css(".col-auto").first

    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("hook-extra-class")
    expect(classes.size).to be > 1
  end

  it "appends a caller-supplied class instead of replacing the component's own" do
    fragment = component_fragment(:page_header, title: "Dashboard", html: { class: "extra" })
    element = fragment.css(".page-header").first

    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("extra")
    expect(classes).to include("page-header")
  end

  it "renders the buttons slot's content in a right-aligned column" do
    fragment = component_fragment(:page_header, title: "Dashboard") do |slots|
      slots.buttons { "<button>New report</button>".html_safe }
    end

    expect(fragment.css(".col-auto button").text).to eq("New report")
  end

  it "renders no buttons column when the block is omitted" do
    fragment = component_fragment(:page_header, title: "Dashboard")

    expect(fragment.css(".col-auto")).to be_empty
  end

  it "renders no buttons column when the block yields no buttons slot content" do
    fragment = component_fragment(:page_header, title: "Dashboard") { |_slots| }

    expect(fragment.css(".col-auto")).to be_empty
  end
end
