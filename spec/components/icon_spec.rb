# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Icon", type: :component do
  it "renders with only the mandatory icon argument" do
    fragment = component_fragment(:icon, icon: "user")

    expect(fragment.css("svg")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :icon, { icon: "user" },
    hook: :html, selector: "svg.icon-tabler-user"

  it "appends a caller class to the icon's own baked-in classes, not replacing them" do
    fragment = component_fragment(:icon, icon: "user", html: { class: "hook-extra-class" })
    classes = fragment.css("svg").first["class"].split(/\s+/)

    expect(classes).to include("icon", "icon-tabler", "icons-tabler-outline", "icon-tabler-user", "hook-extra-class")
  end

  it "adds a text-<color> class for color:" do
    fragment = component_fragment(:icon, icon: "user", color: "danger")

    expect(fragment.css("svg").first["class"].split(/\s+/)).to include("text-danger")
  end

  it "adds a modifier class for each animation/size option" do
    fragment = component_fragment(:icon, icon: "user", pulse: true, tada: true, rotate: true, size: "lg")
    classes = fragment.css("svg").first["class"].split(/\s+/)

    expect(classes).to include("icon-pulse", "icon-tada", "icon-rotate", "icon-lg")
  end

  it "keeps a caller class alongside an animation class" do
    fragment = component_fragment(:icon, icon: "user", pulse: true, html: { class: "hook-extra-class" })
    classes = fragment.css("svg").first["class"].split(/\s+/)

    expect(classes).to include("icon-pulse", "hook-extra-class")
  end

  it "renders title: as a title attribute on the root svg" do
    fragment = component_fragment(:icon, icon: "user", title: "User icon")

    expect(fragment.css("svg").first["title"]).to eq("User icon")
  end

  it "escapes a caller-supplied title" do
    html = render_component(:icon, icon: "user", title: "<script>alert(1)</script>")

    expect(html).not_to include("<script>")
    expect(html).to include("&lt;script&gt;")
  end

  it "falls back to the error icon for an unknown icon name, rather than raising" do
    fragment = component_fragment(:icon, icon: "not-a-real-icon-xyz")

    expect(fragment.css("svg.icon-tabler-bug")).not_to be_empty
  end

  it "does not escape the icons directory for a name containing ../" do
    fragment = component_fragment(:icon, icon: "../../../../../../etc/passwd")

    expect(fragment.css("svg.icon-tabler-bug")).not_to be_empty
  end

  # Regression test for the bug rule 5 fixed: the old add_animation_classes
  # did `data.gsub(/(class="...)/)  { ... }` -- a *global* substitution that
  # appended classes to every class="" in the file, including nested
  # elements. No shipped icon happens to have a nested class="" (so the bug
  # never showed up against real assets), so this stubs Component#read_svg
  # with a synthetic SVG that does, to prove the rewrite is now scoped to
  # the root <svg> tag only.
  it "only rewrites the root <svg> tag, leaving nested elements' classes untouched" do
    nested_svg = <<~SVG
      <svg class="icon icon-tabler icon-tabler-test" width="24" height="24"><path class="inner" d="M0 0" /></svg>
    SVG

    component = TablerUi::Icon::Component.new("test", html: { class: "hook-extra-class" })
    allow(component).to receive(:read_svg).and_return(nested_svg)

    fragment = Nokogiri::HTML5.fragment(component.icon_data)

    root_classes = fragment.css("svg").first["class"].split(/\s+/)
    nested_classes = fragment.css("path").first["class"].split(/\s+/)

    expect(root_classes).to include("hook-extra-class")
    expect(nested_classes).to eq(["inner"])
  end
end
