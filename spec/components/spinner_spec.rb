# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Spinner", type: :component do
  it "renders with no arguments at all, defaulting to spinner-border" do
    fragment = component_fragment(:spinner)
    element = fragment.css("div.spinner-border").first

    expect(element).not_to be_nil
    expect(fragment.css("div.spinner-grow")).to be_empty
  end

  it_behaves_like "an element with an html hook", :spinner, {},
    hook: :html, selector: ".spinner-border"

  it "appends a caller class to the spinner's own classes, not replacing them" do
    fragment = component_fragment(:spinner, html: { class: "hook-extra-class" })
    classes = fragment.css(".spinner-border").first["class"].split(/\s+/)

    expect(classes).to include("spinner-border", "hook-extra-class")
  end

  it "renders spinner-grow (not spinner-border) for type: :grow" do
    fragment = component_fragment(:spinner, type: :grow)

    expect(fragment.css("div.spinner-grow")).not_to be_empty
    expect(fragment.css("div.spinner-border")).to be_empty
  end

  it "accepts type: as a string too" do
    fragment = component_fragment(:spinner, type: "grow")

    expect(fragment.css("div.spinner-grow")).not_to be_empty
  end

  it "raises ArgumentError naming spinner for an unknown type" do
    expect { component_fragment(:spinner, type: :bogus) }
      .to raise_error(ArgumentError, /bogus/)
    expect { component_fragment(:spinner, type: :bogus) }
      .to raise_error(ArgumentError, /border/)
  end

  it "adds spinner-border-sm for size: 'sm' on the border type" do
    fragment = component_fragment(:spinner, size: "sm")

    expect(fragment.css(".spinner-border").first["class"].split(/\s+/)).to include("spinner-border-sm")
  end

  it "adds spinner-grow-sm for size: 'sm' on the grow type" do
    fragment = component_fragment(:spinner, type: :grow, size: "sm")

    expect(fragment.css(".spinner-grow").first["class"].split(/\s+/)).to include("spinner-grow-sm")
  end

  it "adds text-<color> for color:" do
    fragment = component_fragment(:spinner, color: "blue")

    expect(fragment.css(".spinner-border").first["class"].split(/\s+/)).to include("text-blue")
  end

  it "raises ArgumentError naming spinner for an unknown color" do
    expect { component_fragment(:spinner, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:spinner, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /spinner/)
  end

  it "renders a default, visually-hidden accessible label" do
    fragment = component_fragment(:spinner)
    label = fragment.css(".spinner-border .visually-hidden").first

    expect(label).not_to be_nil
    expect(label.text).to eq("Loading...")
  end

  it "lets a caller override the accessible label" do
    fragment = component_fragment(:spinner, label: "Saving...")
    label = fragment.css(".spinner-border .visually-hidden").first

    expect(label.text).to eq("Saving...")
  end

  it "has role=\"status\" on the root element" do
    fragment = component_fragment(:spinner)

    expect(fragment.css(".spinner-border").first["role"]).to eq("status")
  end
end
