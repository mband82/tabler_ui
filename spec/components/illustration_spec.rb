# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Illustration", type: :component do
  it "renders with only the mandatory name argument" do
    fragment = component_fragment(:illustration, name: "boy")

    expect(fragment.css("svg")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :illustration, { name: "boy" },
    hook: :html, selector: "svg.illustration"

  it "appends a caller class to the illustration's own classes, not replacing them" do
    fragment = component_fragment(:illustration, name: "boy", html: { class: "hook-extra-class" })
    classes = fragment.css("svg").first["class"].split(/\s+/)

    expect(classes).to include("illustration", "hook-extra-class")
  end

  it "loads from the dark asset directory for theme: \"dark\" and light for theme: \"light\"" do
    light = render_component(:illustration, name: "boy", theme: "light")
    dark = render_component(:illustration, name: "boy", theme: "dark")

    expect(light).not_to eq(dark)
  end

  it "defaults to the light theme" do
    default_render = render_component(:illustration, name: "boy")
    light_render = render_component(:illustration, name: "boy", theme: "light")

    expect(default_render).to eq(light_render)
  end

  # Regression test for the variant: -> theme: rename: variant: is not a
  # recognized option any more, so passing it must NOT select the dark
  # asset -- the component still falls back to its "light" default.
  it "ignores variant: (renamed to theme:) and still renders the light asset" do
    default_render = render_component(:illustration, name: "boy")
    variant_render = render_component(:illustration, name: "boy", variant: "dark")

    expect(variant_render).to eq(default_render)
  end

  it "sets width/height for size: :md, scaling height proportionally from the viewBox" do
    fragment = component_fragment(:illustration, name: "boy", size: :md)
    svg = fragment.css("svg").first

    expect(svg["width"]).to eq("200")
    expect(svg["height"]).to eq((200 * 600.0 / 800.0).round.to_s)
  end

  it "sets width/height for a raw integer size, scaling height proportionally from the viewBox" do
    fragment = component_fragment(:illustration, name: "boy", size: 320)
    svg = fragment.css("svg").first

    expect(svg["width"]).to eq("320")
    expect(svg["height"]).to eq((320 * 600.0 / 800.0).round.to_s)
  end

  it "falls back to the not-found SVG for an unknown illustration name, rather than raising" do
    fragment = component_fragment(:illustration, name: "not-a-real-illustration-xyz")

    expect(fragment.css("svg.illustration-error")).not_to be_empty
  end

  it "does not escape the illustrations directory for a name containing ../" do
    fragment = component_fragment(:illustration, name: "../../../../../../etc/passwd")

    expect(fragment.css("svg.illustration-error")).not_to be_empty
  end

  # Regression test mirroring icon_spec's: proves the root-tag rewrite is
  # scoped to the root <svg> only, never a global gsub across the file.
  it "only rewrites the root <svg> tag, leaving nested elements' classes untouched" do
    nested_svg = <<~SVG
      <svg width="800" height="600" viewBox="0 0 800 600"><path class="inner" d="M0 0" /></svg>
    SVG

    component = TablerUi::Illustration::Component.new("test", html: { class: "hook-extra-class" })
    allow(component).to receive(:read_svg).and_return(nested_svg)

    fragment = Nokogiri::HTML5.fragment(component.illustration_data)

    root_classes = fragment.css("svg").first["class"].split(/\s+/)
    nested_classes = fragment.css("path").first["class"].split(/\s+/)

    expect(root_classes).to include("hook-extra-class")
    expect(nested_classes).to eq(["inner"])
  end
end
