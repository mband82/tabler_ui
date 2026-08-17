# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Status", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:status)

    expect(fragment.css("span.status")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :status, {},
    hook: :html, selector: "span.status"

  it_behaves_like "an element with an html hook", :status, { dot: true },
    hook: :dot_html, selector: "span.status-dot"

  it "appends a caller class to the root span's own class, not replacing it" do
    fragment = component_fragment(:status, html: { class: "hook-extra-class" })
    classes = fragment.css("span.status").first["class"].split(/\s+/)

    expect(classes).to include("status", "status-blue", "hook-extra-class")
  end

  it "renders a status-dot class when dot: true" do
    fragment = component_fragment(:status, dot: true)

    expect(fragment.css("span.status > span.status-dot")).not_to be_empty
  end

  it "renders a status-dot-animated class when animated: true" do
    fragment = component_fragment(:status, dot: true, animated: true)

    expect(fragment.css("span.status-dot-animated")).not_to be_empty
  end

  it "renders a status-lite class when light: true" do
    fragment = component_fragment(:status, light: true)

    expect(fragment.css("span.status-lite")).not_to be_empty
  end

  it "renders a standalone status-dot when standalone: true" do
    fragment = component_fragment(:status, standalone: true, dot: true)

    span = fragment.css("span").first
    expect(span["class"].split(/\s+/)).to include("status-dot")
    expect(span.text).to be_empty
  end

  it "renders a status-indicator with 3 circles when indicator: true" do
    fragment = component_fragment(:status, indicator: true)

    expect(fragment.css("span.status-indicator")).not_to be_empty
    expect(fragment.css("span.status-indicator-circle").size).to eq(3)
  end

  it "accepts color: 'primary' and renders status-primary, not a silent fallback to blue" do
    fragment = component_fragment(:status, color: "primary")

    classes = fragment.css("span.status").first["class"].split(/\s+/)
    expect(classes).to include("status-primary")
    expect(classes).not_to include("status-blue")
  end

  it "raises ArgumentError naming status for an unknown color" do
    expect { component_fragment(:status, color: "primry") }
      .to raise_error(ArgumentError, /status/)
  end

  it "defaults color to blue when omitted" do
    fragment = component_fragment(:status)

    expect(fragment.css("span.status").first["class"].split(/\s+/)).to include("status-blue")
  end

  it "no longer supports lite: (renamed to light:)" do
    fragment = component_fragment(:status, lite: true)

    expect(fragment.css("span.status-lite")).to be_empty
  end
end
