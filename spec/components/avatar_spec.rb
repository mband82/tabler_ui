# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Avatar", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:avatar)

    expect(fragment.css(".avatar")).not_to be_empty
  end

  it "renders initials mode as a <span class=\"avatar\">" do
    fragment = component_fragment(:avatar, initials: "JD")
    element = fragment.css("span.avatar").first

    expect(element).not_to be_nil
    expect(element.text).to include("JD")
    expect(element["style"]).to match(/background-color: hsl\(/)
  end

  it "renders image mode as a <span class=\"avatar\"> with a background-image style" do
    fragment = component_fragment(:avatar, image: "https://example.com/pic.png")
    element = fragment.css("span.avatar").first

    expect(element).not_to be_nil
    expect(element["style"]).to eq("background-image: url(https://example.com/pic.png)")
  end

  it "renders the generated identicon mode as an <svg class=\"avatar\"> when neither image: nor initials: is given" do
    fragment = component_fragment(:avatar, name: "Ada Lovelace")
    element = fragment.css("svg.avatar").first

    expect(element).not_to be_nil
    expect(fragment.css("svg.avatar circle, svg.avatar rect").size).to eq(5)
  end

  it "gives image: precedence over initials:" do
    fragment = component_fragment(:avatar, image: "https://example.com/pic.png", initials: "JD")

    expect(fragment.css("span.avatar").first["style"]).to include("background-image")
    expect(fragment.css("span.avatar").first.text.strip).to eq("")
  end

  it_behaves_like "an element with an html hook", :avatar, {},
    hook: :html, selector: ".avatar"

  it_behaves_like "an element with an html hook", :avatar, { show_details: true, title: "Jane Doe" },
    hook: :details_html, selector: "div.ps-2"

  it "appends a caller class to the avatar's own classes, not replacing them" do
    fragment = component_fragment(:avatar, initials: "JD", html: { class: "hook-extra-class" })
    classes = fragment.css(".avatar").first["class"].split(/\s+/)

    expect(classes).to include("avatar", "hook-extra-class")
  end

  it "adds avatar-<size> for size:, defaulting to avatar-sm" do
    fragment = component_fragment(:avatar, initials: "JD")
    expect(fragment.css(".avatar").first["class"].split(/\s+/)).to include("avatar-sm")

    fragment = component_fragment(:avatar, initials: "JD", size: "xl")
    expect(fragment.css(".avatar").first["class"].split(/\s+/)).to include("avatar-xl")
  end

  it "adds rounded-<shape> for shape:, defaulting to rounded for initials/image and rounded-0 for the generated identicon" do
    fragment = component_fragment(:avatar, initials: "JD")
    expect(fragment.css(".avatar").first["class"].split(/\s+/)).to include("rounded")

    fragment = component_fragment(:avatar, name: "Ada Lovelace")
    expect(fragment.css(".avatar").first["class"].split(/\s+/)).to include("rounded-0")

    fragment = component_fragment(:avatar, initials: "JD", shape: "circle")
    expect(fragment.css(".avatar").first["class"].split(/\s+/)).to include("rounded-circle")
  end

  it "renders the details block only when show_details: is true" do
    fragment = component_fragment(:avatar, initials: "JD")
    expect(fragment.css("div.ps-2")).to be_empty

    fragment = component_fragment(:avatar, initials: "JD", show_details: true, title: "Jane Doe", subtitle: "Admin")
    details = fragment.css("div.ps-2").first

    expect(details).not_to be_nil
    expect(details.text).to include("Jane Doe")
    expect(details.text).to include("Admin")
  end

  # --- Regression: srand(seed) used to reseed Ruby's *global* RNG on every
  # render, so rendering an avatar changed the outcome of every subsequent
  # `rand` call in the process (session tokens, other components, other
  # specs). Fixed by scoping to an instance-local Random.new(seed) in
  # TablerUi::Avatar::Component#identicon_shapes.
  it "does not disturb the global random number generator (regression: srand used to mutate it)" do
    srand(12_345)
    expected_next_rand = rand
    srand(12_345)

    component_fragment(:avatar, name: "Ada Lovelace")

    expect(rand).to eq(expected_next_rand)
  end

  # --- Determinism: fixing the RNG scoping must not break "same name ->
  # same avatar" -- Random.new(seed) produces a different sequence than
  # srand(seed) + rand did, but it must still be reproducible.
  it "renders byte-identical output for the same name every time (determinism)" do
    first = render_component(:avatar, name: "Ada Lovelace")
    second = render_component(:avatar, name: "Ada Lovelace")

    expect(first).to eq(second)
  end

  # --- Regression: `def rand_color` used to live inside the ERB template
  # body, which compiles to a method on the shared ActionView::Base
  # subclass -- redefining it on every single render. Fixed by moving it to
  # a private method on TablerUi::Avatar::Component.
  it "does not define rand_color on the shared view class (regression: it used to be defined inside the ERB template body)" do
    component_fragment(:avatar, name: "Ada Lovelace")

    expect(tabler_ui_view_context).not_to respond_to(:rand_color)
    expect(TablerUi::Avatar::Component.private_method_defined?(:rand_color)).to be true
  end
end
