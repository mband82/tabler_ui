# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Alert", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:alert)

    expect(fragment.css("div.alert")).not_to be_empty
    expect(fragment.css(".alert").first["role"]).to eq("alert")
  end

  it_behaves_like "an element with an html hook", :alert, {},
    hook: :html, selector: ".alert"

  it_behaves_like "an element with an html hook", :alert, { title: "Error" },
    hook: :title_html, selector: ".alert-title"

  it_behaves_like "an element with an html hook", :alert, {},
    hook: :icon_html, selector: ".alert-icon-wrapper"

  it "appends a caller class to the alert's own classes, not replacing them" do
    fragment = component_fragment(:alert, color: "danger", html: { class: "hook-extra-class" })
    classes = fragment.css(".alert").first["class"].split(/\s+/)

    expect(classes).to include("alert", "alert-danger", "hook-extra-class")
  end

  it "defaults to alert-info when color: is omitted" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-info")
  end

  it "produces alert-<color> for a given color" do
    fragment = component_fragment(:alert, color: "danger")

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-danger")
  end

  it "raises ArgumentError naming alert for an unknown color" do
    expect { component_fragment(:alert, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:alert, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /alert/)
  end

  it "no longer accepts variant: -- passing it has no effect (rename regression)" do
    fragment = component_fragment(:alert, variant: "danger", text: "Hi")
    classes = fragment.css(".alert").first["class"].split(/\s+/)

    expect(classes).not_to include("alert-danger")
    expect(classes).to include("alert-info")
  end

  it "no longer accepts message: -- passing it renders nothing (rename regression)" do
    fragment = component_fragment(:alert, message: "Old message")

    expect(fragment.to_html).not_to include("Old message")
  end

  it "no longer accepts link: -- passing it renders no action link (rename regression)" do
    fragment = component_fragment(:alert, link: "/somewhere", link_text: "Go")

    expect(fragment.css(".alert-link")).to be_empty
  end

  it "renders text: in a text-secondary div" do
    fragment = component_fragment(:alert, text: "Saved!")

    expect(fragment.css(".text-secondary").text).to eq("Saved!")
  end

  it "renders the body slot's rich content when text: is omitted" do
    fragment = component_fragment(:alert) do |slots|
      slots.body { "<strong>Bold</strong>".html_safe }
    end

    expect(fragment.css("strong").text).to eq("Bold")
  end

  it "renders no body content when neither text: nor the body slot are given" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".text-secondary")).to be_empty
  end

  it "renders title: in an h4.alert-title" do
    fragment = component_fragment(:alert, title: "Error")

    expect(fragment.css("h4.alert-title").text).to eq("Error")
  end

  it "renders no title element when title: is omitted" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".alert-title")).to be_empty
  end

  it "renders a default icon based on color" do
    fragment = component_fragment(:alert, color: "danger")

    expect(fragment.css(".icon-tabler-alert-circle")).not_to be_empty
  end

  it "renders a custom icon: instead of the color's default" do
    fragment = component_fragment(:alert, color: "danger", icon: "download")

    expect(fragment.css(".icon-tabler-download")).not_to be_empty
    expect(fragment.css(".icon-tabler-alert-circle")).to be_empty
  end

  it "renders no icon when icon: false" do
    fragment = component_fragment(:alert, icon: false)

    expect(fragment.css(".alert-icon-wrapper")).to be_empty
    expect(fragment.css("svg")).to be_empty
  end

  it "renders a dismiss button and alert-dismissible class for dismissible: true" do
    fragment = component_fragment(:alert, dismissible: true)

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-dismissible")
    expect(fragment.css("a.btn-close[data-bs-dismiss='alert']")).not_to be_empty
  end

  it "renders no dismiss button when dismissible: is omitted" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".btn-close")).to be_empty
  end

  it "adds alert-important for important: true" do
    fragment = component_fragment(:alert, important: true)

    expect(fragment.css(".alert").first["class"].split(/\s+/)).to include("alert-important")
  end

  it "renders url: and link_text: as the action link" do
    fragment = component_fragment(:alert, url: "/changelog", link_text: "See what's new")
    link = fragment.css("a.alert-link").first

    expect(link).not_to be_nil
    expect(link["href"]).to eq("/changelog")
    expect(link.text).to eq("See what's new")
  end

  it "defaults link_text: to 'Learn more' when url: is given without link_text:" do
    fragment = component_fragment(:alert, url: "/changelog")

    expect(fragment.css("a.alert-link").text).to eq("Learn more")
  end

  it "renders no action link when url: is omitted" do
    fragment = component_fragment(:alert)

    expect(fragment.css(".alert-link")).to be_empty
  end
end
