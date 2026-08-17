# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Empty", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:empty)

    expect(fragment.css(".empty")).not_to be_empty
    expect(fragment.css(".empty-img")).to be_empty
    expect(fragment.css(".empty-icon")).to be_empty
    expect(fragment.css(".empty-header")).to be_empty
    expect(fragment.css(".empty-title")).to be_empty
    expect(fragment.css(".empty-subtitle")).to be_empty
    expect(fragment.css(".empty-action")).to be_empty
  end

  it_behaves_like "an element with an html hook", :empty, {},
    hook: :html, selector: ".empty"

  it_behaves_like "an element with an html hook", :empty, { image: "search" },
    hook: :img_html, selector: ".empty-img"

  it_behaves_like "an element with an html hook", :empty, { icon: "mood-empty" },
    hook: :icon_html, selector: ".empty-icon"

  it_behaves_like "an element with an html hook", :empty, { header: "404" },
    hook: :header_html, selector: ".empty-header"

  it_behaves_like "an element with an html hook", :empty, { title: "No results found" },
    hook: :title_html, selector: ".empty-title"

  it_behaves_like "an element with an html hook", :empty, { subtitle: "Try adjusting your filter." },
    hook: :subtitle_html, selector: ".empty-subtitle"

  it "passes id/data/class through action_html: onto the .empty-action" do
    fragment = component_fragment(:empty, action_html: { class: "hook-extra-class", id: "hook-test-id",
                                                           data: { testid: "hook-test-data" } }) do |slots|
      slots.action { "Content" }
    end
    element = fragment.css(".empty-action").first

    expect(element).not_to be_nil
    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("empty-action", "hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it "renders title: as a p.empty-title" do
    fragment = component_fragment(:empty, title: "No results found")

    expect(fragment.css(".empty-title").text).to eq("No results found")
  end

  it "renders no .empty-title when title: is omitted" do
    fragment = component_fragment(:empty)

    expect(fragment.css(".empty-title")).to be_empty
  end

  it "renders subtitle: as a p.empty-subtitle" do
    fragment = component_fragment(:empty, subtitle: "Try adjusting your search or filter.")

    expect(fragment.css(".empty-subtitle").text).to eq("Try adjusting your search or filter.")
  end

  it "renders no .empty-subtitle when subtitle: is omitted" do
    fragment = component_fragment(:empty)

    expect(fragment.css(".empty-subtitle")).to be_empty
  end

  it "renders header: inside .empty-header when no header slot is given" do
    fragment = component_fragment(:empty, header: "404")

    expect(fragment.css(".empty-header").text.strip).to eq("404")
  end

  it "renders no .empty-header when header: is omitted and no header slot is given" do
    fragment = component_fragment(:empty)

    expect(fragment.css(".empty-header")).to be_empty
  end

  it "adds empty-bordered for bordered: true" do
    fragment = component_fragment(:empty, bordered: true)

    expect(fragment.css(".empty").first["class"].split(/\s+/)).to include("empty-bordered")
  end

  it "renders no empty-bordered class by default" do
    fragment = component_fragment(:empty)

    expect(fragment.css(".empty").first["class"].split(/\s+/)).not_to include("empty-bordered")
  end

  it "renders icon: as a real icon inside .empty-icon, not the error-fallback bug icon" do
    fragment = component_fragment(:empty, icon: "mood-empty")

    expect(fragment.css(".empty-icon svg.icon-tabler-mood-empty")).not_to be_empty
    expect(fragment.css(".empty-icon svg.icon-tabler-bug")).to be_empty
  end

  it "renders no .empty-icon when icon: is omitted and no icon slot is given" do
    fragment = component_fragment(:empty)

    expect(fragment.css(".empty-icon")).to be_empty
  end

  it "renders image: as an illustration inside .empty-img when no img slot is given" do
    fragment = component_fragment(:empty, image: "search")

    expect(fragment.css(".empty-img svg.illustration")).not_to be_empty
  end

  it "renders no .empty-img when image: is omitted and no img slot is given" do
    fragment = component_fragment(:empty)

    expect(fragment.css(".empty-img")).to be_empty
  end

  it "renders the action slot's content inside .empty-action" do
    fragment = component_fragment(:empty) do |slots|
      slots.action { '<a href="#" class="btn btn-primary">New item</a>'.html_safe }
    end

    expect(fragment.css(".empty-action .btn").text.strip).to eq("New item")
  end

  it "renders no .empty-action when the action slot is omitted" do
    fragment = component_fragment(:empty)

    expect(fragment.css(".empty-action")).to be_empty
  end

  it "prefers an img slot over image: when both are given" do
    fragment = component_fragment(:empty, image: "search") do |slots|
      slots.img { "<img src=\"/custom.svg\" alt=\"\">".html_safe }
    end

    expect(fragment.css(".empty-img img").attribute("src").to_s).to eq("/custom.svg")
    expect(fragment.css(".empty-img svg.illustration")).to be_empty
  end

  it "prefers an icon slot over icon: when both are given" do
    fragment = component_fragment(:empty, icon: "mood-empty") do |slots|
      slots.icon { "<span class=\"custom-icon\"></span>".html_safe }
    end

    expect(fragment.css(".empty-icon .custom-icon")).not_to be_empty
    expect(fragment.css(".empty-icon svg.icon-tabler-mood-empty")).to be_empty
  end

  it "prefers a header slot over header: when both are given" do
    fragment = component_fragment(:empty, header: "Ignored header") do |slots|
      slots.header { "Custom header".html_safe }
    end

    expect(fragment.css(".empty-header").text.strip).to eq("Custom header")
    expect(fragment.to_html).not_to include("Ignored header")
  end
end
