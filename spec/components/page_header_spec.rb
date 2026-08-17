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

  it "no longer accepts subtitle: -- passing it renders no pretitle (rename regression)" do
    fragment = component_fragment(:page_header, title: "Dashboard", subtitle: "Overview")

    expect(fragment.css(".page-pretitle")).to be_empty
    expect(fragment.to_html).not_to include("Overview")
  end

  it_behaves_like "an element with an html hook", :page_header, {},
    hook: :html, selector: ".page-header"

  it_behaves_like "an element with an html hook", :page_header, { title: "Dashboard" },
    hook: :title_html, selector: ".page-title"

  it_behaves_like "an element with an html hook", :page_header, { title: "Dashboard", pretitle: "Overview" },
    hook: :pretitle_html, selector: ".page-pretitle"

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
