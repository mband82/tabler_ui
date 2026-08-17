# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Badge", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:badge)

    expect(fragment.css("span.badge")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :badge, {},
    hook: :html, selector: ".badge"

  it "appends a caller class to the badge's own classes, not replacing them" do
    fragment = component_fragment(:badge, text: "New", color: "blue", html: { class: "hook-extra-class" })
    classes = fragment.css(".badge").first["class"].split(/\s+/)

    expect(classes).to include("badge", "bg-blue", "hook-extra-class")
  end

  it "renders an <a> when url: is given" do
    fragment = component_fragment(:badge, text: "Click me", url: "/path")
    element = fragment.css("a.badge").first

    expect(element).not_to be_nil
    expect(element["href"]).to eq("/path")
    expect(fragment.css("span.badge")).to be_empty
  end

  it "renders a <span> when no url: is given" do
    fragment = component_fragment(:badge, text: "New")

    expect(fragment.css("span.badge")).not_to be_empty
    expect(fragment.css("a.badge")).to be_empty
  end

  it "adds bg-<color>-lt for light: true" do
    fragment = component_fragment(:badge, color: "yellow", light: true)
    classes = fragment.css(".badge").first["class"].split(/\s+/)

    expect(classes).to include("bg-yellow-lt", "text-yellow-lt-fg")
  end

  it "adds badge-pill for pill: true" do
    fragment = component_fragment(:badge, text: "4", color: "red", pill: true)

    expect(fragment.css(".badge").first["class"].split(/\s+/)).to include("badge-pill")
  end

  it "adds badge-notification for notification: true" do
    fragment = component_fragment(:badge, color: "red", notification: true)

    expect(fragment.css(".badge").first["class"].split(/\s+/)).to include("badge-notification")
  end

  it "adds badge-blink for blink: true" do
    fragment = component_fragment(:badge, color: "red", notification: true, blink: true)

    expect(fragment.css(".badge").first["class"].split(/\s+/)).to include("badge-blink")
  end

  it "adds badge-outline for outline: true" do
    fragment = component_fragment(:badge, text: "Draft", color: "secondary", outline: true)

    expect(fragment.css(".badge").first["class"].split(/\s+/)).to include("badge-outline")
  end

  it "adds badge-<size> for size:" do
    fragment = component_fragment(:badge, text: "Small", color: "green", size: :sm)
    expect(fragment.css(".badge").first["class"].split(/\s+/)).to include("badge-sm")

    fragment = component_fragment(:badge, text: "Large", color: "green", size: :lg)
    expect(fragment.css(".badge").first["class"].split(/\s+/)).to include("badge-lg")
  end

  it "raises ArgumentError naming badge for an unknown color" do
    expect { component_fragment(:badge, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:badge, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /badge/)
  end

  it "accepts a Tabler palette color" do
    fragment = component_fragment(:badge, text: "New", color: "blue")

    expect(fragment.css(".badge").first["class"].split(/\s+/)).to include("bg-blue")
  end

  it "accepts a Bootstrap semantic color" do
    fragment = component_fragment(:badge, text: "New", color: "primary")

    expect(fragment.css(".badge").first["class"].split(/\s+/)).to include("bg-primary")
  end

  it "escapes unsafe content" do
    fragment = component_fragment(:badge, content: "<script>alert(1)</script>")

    expect(fragment.to_html).not_to include("<script>")
    expect(fragment.to_html).to include("&lt;script&gt;")
  end

  it "does not escape content that already arrived as an ActiveSupport::SafeBuffer" do
    fragment = component_fragment(:badge, content: "<strong>Bold</strong>".html_safe)

    expect(fragment.css(".badge strong")).not_to be_empty
  end

  it "adds badge-dot for dot: true and renders no children" do
    fragment = component_fragment(:badge, color: "red", dot: true)
    element = fragment.css(".badge").first

    expect(element["class"].split(/\s+/)).to include("badge-dot")
    expect(element.text.strip).to eq("")
  end

  it "raises ArgumentError when dot: is combined with text:" do
    expect { component_fragment(:badge, color: "red", dot: true, text: "New") }
      .to raise_error(ArgumentError, /dot/)
  end

  it "raises ArgumentError when dot: is combined with icon:" do
    expect { component_fragment(:badge, color: "red", dot: true, icon: "star") }
      .to raise_error(ArgumentError, /dot/)
  end

  it "raises ArgumentError when dot: is combined with content:" do
    expect { component_fragment(:badge, color: "red", dot: true, content: "New") }
      .to raise_error(ArgumentError, /dot/)
  end

  it "adds badge-icononly for icon_only: true with an icon" do
    fragment = component_fragment(:badge, color: "blue", icon: "star", icon_only: true)

    expect(fragment.css(".badge").first["class"].split(/\s+/)).to include("badge-icononly")
  end

  it "raises ArgumentError when icon_only: is combined with text:" do
    expect { component_fragment(:badge, color: "blue", icon: "star", icon_only: true, text: "New") }
      .to raise_error(ArgumentError, /icon_only/)
  end

  it "raises ArgumentError when icon_only: is combined with content:" do
    expect { component_fragment(:badge, color: "blue", icon: "star", icon_only: true, content: "New") }
      .to raise_error(ArgumentError, /icon_only/)
  end

  it "still emits badge-notification for notification: true, unaffected by dot/icon_only" do
    fragment = component_fragment(:badge, color: "red", notification: true)
    classes = fragment.css(".badge").first["class"].split(/\s+/)

    expect(classes).to include("badge-notification")
    expect(classes).not_to include("badge-dot", "badge-icononly")
  end
end
