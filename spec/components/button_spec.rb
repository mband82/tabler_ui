# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Button", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:button)

    expect(fragment.css("a.btn")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :button, {}, hook: :html, selector: ".btn"

  it "appends a caller class to the button's own classes, not replacing them" do
    fragment = component_fragment(:button, text: "Save", color: "blue", html: { class: "hook-extra-class" })
    classes = fragment.css(".btn").first["class"].split(/\s+/)

    expect(classes).to include("btn", "btn-blue", "hook-extra-class")
  end

  it "renders an <a> for method: :get (the default)" do
    fragment = component_fragment(:button, text: "Click me", url: "/path")
    element = fragment.css("a.btn").first

    expect(element).not_to be_nil
    expect(element["href"]).to eq("/path")
    expect(fragment.css("form")).to be_empty
  end

  it "renders a form/button for method: :delete" do
    fragment = component_fragment(:button, text: "Delete", url: "/path", method: :delete)

    expect(fragment.css("form")).not_to be_empty
    expect(fragment.css("form button.btn")).not_to be_empty
    expect(fragment.css("a.btn")).to be_empty
  end

  it "adds btn-<color> for color:" do
    fragment = component_fragment(:button, text: "Save", color: "green")

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-green")
  end

  it "adds btn-outline-<color> for outline: true" do
    fragment = component_fragment(:button, text: "Save", color: "green", outline: true)

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-outline-green")
  end

  it "adds btn-<size> for size:" do
    fragment = component_fragment(:button, text: "Save", size: :sm)

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-sm")
  end

  it "adds btn-pill for shape: pill, not rounded-pill" do
    fragment = component_fragment(:button, text: "Save", shape: "pill")
    classes = fragment.css(".btn").first["class"].split(/\s+/)

    expect(classes).to include("btn-pill")
    expect(classes).not_to include("rounded-pill")
  end

  it "adds btn-square for shape: square" do
    fragment = component_fragment(:button, text: "Save", shape: "square")

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-square")
  end

  it "adds btn-icon for icon_only: true" do
    fragment = component_fragment(:button, icon: "star", icon_only: true)

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-icon")
  end

  it "adds both btn-pill and btn-icon for shape: pill combined with icon_only: true" do
    fragment = component_fragment(:button, icon: "star", icon_only: true, shape: "pill")
    classes = fragment.css(".btn").first["class"].split(/\s+/)

    expect(classes).to include("btn-pill", "btn-icon")
  end

  it "adds btn-loading for loading: true" do
    fragment = component_fragment(:button, text: "Save", loading: true)

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-loading")
  end

  it "adds btn-floating for floating: true" do
    fragment = component_fragment(:button, text: "Save", floating: true)

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-floating")
  end

  it "adds only the base btn-animate-icon class for animate_icon: true" do
    fragment = component_fragment(:button, text: "Save", animate_icon: true)
    classes = fragment.css(".btn").first["class"].split(/\s+/)

    expect(classes).to include("btn-animate-icon")
    expect(classes.grep(/^btn-animate-icon-/)).to be_empty
  end

  %w[rotate shake tada pulse move-start].each do |modifier|
    it "adds btn-animate-icon and btn-animate-icon-#{modifier} for animate_icon: #{modifier.inspect}" do
      fragment = component_fragment(:button, text: "Save", animate_icon: modifier)
      classes = fragment.css(".btn").first["class"].split(/\s+/)

      expect(classes).to include("btn-animate-icon", "btn-animate-icon-#{modifier}")
    end
  end

  it "raises ArgumentError for an unknown animate_icon value" do
    expect { component_fragment(:button, text: "Save", animate_icon: "spin") }
      .to raise_error(ArgumentError, /spin/)
  end

  it "adds btn-ghost alongside btn-<color> for ghost: true" do
    fragment = component_fragment(:button, text: "Save", color: "green", ghost: true)
    classes = fragment.css(".btn").first["class"].split(/\s+/)

    expect(classes).to include("btn-ghost", "btn-green")
  end

  it "raises ArgumentError when ghost: true is combined with outline: true" do
    expect { component_fragment(:button, text: "Save", ghost: true, outline: true) }
      .to raise_error(ArgumentError, /outline/)
  end

  it "accepts a brand color and emits btn-<brand>" do
    fragment = component_fragment(:button, text: "Save", color: "github")

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-github")
  end

  it "accepts the muted color and emits btn-muted" do
    fragment = component_fragment(:button, text: "Save", color: "muted")

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-muted")
  end

  it "accepts a brand color combined with outline: true and emits btn-outline-<brand>" do
    fragment = component_fragment(:button, text: "Save", color: "github", outline: true)

    expect(fragment.css(".btn").first["class"].split(/\s+/)).to include("btn-outline-github")
  end

  it "does not leak brand colors into the badge component's shared palette" do
    expect { component_fragment(:badge, text: "Save", color: "github") }
      .to raise_error(ArgumentError)
  end

  it "passes disabled through to the rendered element" do
    fragment = component_fragment(:button, text: "Save", disabled: true)

    expect(fragment.css(".btn").first["disabled"]).not_to be_nil
  end

  it "raises ArgumentError naming button for an unknown color" do
    expect { component_fragment(:button, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:button, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /button/)
  end

  it "no longer accepts variant: -- it does not colour the button" do
    fragment = component_fragment(:button, text: "Save", variant: "green")
    classes = fragment.css(".btn").first["class"].split(/\s+/)

    expect(classes).not_to include("btn-green")
    expect(classes).to include("btn-primary")
  end

  it "no longer accepts to: -- it does not set the href" do
    fragment = component_fragment(:button, text: "Save", to: "/somewhere")

    expect(fragment.css("a.btn").first["href"]).not_to eq("/somewhere")
  end

  it "renders the real icon svg alongside the text, not the error fallback" do
    fragment = component_fragment(:button, text: "Star", icon: "star")
    svg = fragment.css(".btn svg").first

    expect(svg).not_to be_nil
    expect(fragment.to_html).to include("Star")
    expect(svg["class"].to_s).not_to include("icon-tabler-bug")
  end

  it "merges caller data: with the component's own data attributes rather than clobbering them" do
    fragment = component_fragment(:button, text: "Save", data: { turbo: "false" },
                                             html: { data: { testid: "save-button" } })
    element = fragment.css(".btn").first

    expect(element["data-turbo"]).to eq("false")
    expect(element["data-testid"]).to eq("save-button")
  end

  it "renders data-turbo-confirm on the <a> for method: :get" do
    fragment = component_fragment(:button, text: "Save", url: "/save", confirm: "Are you sure?")
    element = fragment.css("a.btn").first

    expect(element["data-turbo-confirm"]).to eq("Are you sure?")
  end

  it "renders data-turbo-confirm on the button_to <button> for a non-GET method" do
    fragment = component_fragment(:button, text: "Delete", url: "/path", method: :delete,
                                             confirm: "Are you sure?")
    element = fragment.css("form button.btn").first

    expect(element["data-turbo-confirm"]).to eq("Are you sure?")
  end

  it "REGRESSION: confirm: coexists with a caller's data: and the html: hook's data: rather than clobbering them" do
    fragment = component_fragment(:button, text: "Save", url: "/save", confirm: "Are you sure?",
                                             data: { turbo: "false" },
                                             html: { data: { testid: "save-button" } })
    element = fragment.css("a.btn").first

    expect(element["data-turbo-confirm"]).to eq("Are you sure?")
    expect(element["data-turbo"]).to eq("false")
    expect(element["data-testid"]).to eq("save-button")
  end

  it "turbo: true with a non-GET method renders an <a> with data-turbo-method and no <form>" do
    fragment = component_fragment(:button, text: "Delete", url: "/path", method: :delete, turbo: true)
    element = fragment.css("a.btn").first

    expect(fragment.css("form")).to be_empty
    expect(element).not_to be_nil
    expect(element["href"]).to eq("/path")
    expect(element["data-turbo-method"]).to eq("delete")
  end

  it "turbo: true with method: :get is a no-op -- still a plain <a> with no data-turbo-method" do
    fragment = component_fragment(:button, text: "Save", url: "/save", turbo: true)
    element = fragment.css("a.btn").first

    expect(fragment.css("form")).to be_empty
    expect(element["href"]).to eq("/save")
    expect(element["data-turbo-method"]).to be_nil
  end

  it "REGRESSION: turbo: false (the default) with a non-GET method still emits the button_to form" do
    fragment = component_fragment(:button, text: "Delete", url: "/path", method: :delete)

    expect(fragment.css("form")).not_to be_empty
    expect(fragment.css("form button.btn")).not_to be_empty
    expect(fragment.css("a.btn")).to be_empty
  end
end
