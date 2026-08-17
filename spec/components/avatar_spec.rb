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

  describe "cover:" do
    it "adds avatar-cover on top of the image: render" do
      classes = component_fragment(:avatar, image: "https://example.com/pic.png", cover: true)
                  .css(".avatar").first["class"].split(/\s+/)

      expect(classes).to include("avatar-cover")
    end

    it "adds avatar-cover on top of the initials: render" do
      classes = component_fragment(:avatar, initials: "JD", cover: true)
                  .css(".avatar").first["class"].split(/\s+/)

      expect(classes).to include("avatar-cover")
    end

    it "adds avatar-cover on top of the generated identicon render" do
      classes = component_fragment(:avatar, name: "Ada Lovelace", cover: true)
                  .css(".avatar").first["class"].split(/\s+/)

      expect(classes).to include("avatar-cover")
    end

    it "omits avatar-cover when not given" do
      classes = component_fragment(:avatar, initials: "JD").css(".avatar").first["class"].split(/\s+/)

      expect(classes).not_to include("avatar-cover")
    end
  end

  describe "overlay slot" do
    it "renders inside the .avatar element for image:, as a descendant not a sibling" do
      fragment = component_fragment(:avatar, image: "https://example.com/pic.png") do |slots|
        slots.overlay { '<span class="badge bg-success"></span>'.html_safe }
      end

      avatar_element = fragment.css("span.avatar").first
      badge = fragment.css(".badge").first

      expect(badge).not_to be_nil
      expect(badge.parent).to eq(avatar_element)
    end

    it "renders inside the .avatar element for initials:, alongside the initials text" do
      fragment = component_fragment(:avatar, initials: "JD") do |slots|
        slots.overlay { '<span class="badge bg-success"></span>'.html_safe }
      end

      avatar_element = fragment.css("span.avatar").first
      expect(avatar_element.text).to include("JD")
      expect(avatar_element.css(".badge")).not_to be_empty
    end

    it "raises ArgumentError when given to a generated identicon (no image:/initials:)" do
      # The check can only happen once the block's slots are known, which is
      # render time -- and TablerUi::Ui only calls #validate! for
      # builder-style components (avatar is slot-style), so it has to raise
      # from inside the ERB template itself. Rails wraps any error raised
      # during partial rendering in ActionView::Template::Error; the
      # original ArgumentError (with the clear message) is its #cause.
      expect {
        component_fragment(:avatar, name: "Ada Lovelace") { |slots| slots.overlay { "x" } }
      }.to raise_error { |error|
        expect(error.cause).to be_a(ArgumentError)
        expect(error.cause.message).to match(/overlay/i)
      }
    end
  end

  # --- Regression: the image: branch used to be a self-closing tag.span
  # with no block at all. Giving it a do...end block (so the overlay slot
  # has somewhere to render) must not add any stray child nodes inside the
  # <span> when no overlay is passed -- it must still parse as one empty
  # element, not e.g. a stray text/whitespace node.
  it "renders no stray child nodes for image: when no block is passed (regression)" do
    fragment = component_fragment(:avatar, image: "https://example.com/pic.png")
    element = fragment.css("span.avatar").first

    expect(element.children).to be_empty
  end
end
