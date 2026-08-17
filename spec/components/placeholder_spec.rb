# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Placeholder", type: :component do
  it "renders with no arguments at all, defaulting to type: :text" do
    fragment = component_fragment(:placeholder)

    expect(fragment.css("div.placeholder-xs.col-9")).not_to be_empty
  end

  TablerUi::Placeholder::Component::TYPES.each do |type|
    it "renders for type: #{type.inspect}" do
      fragment = component_fragment(:placeholder, type: type)

      expect(fragment.to_html).not_to be_empty
    end
  end

  it "renders the fallback span for a type outside TYPES" do
    fragment = component_fragment(:placeholder, type: :bogus)

    expect(fragment.css("span.placeholder")).not_to be_empty
  end

  # --- rule 5 hooks ------------------------------------------------------

  it_behaves_like "an element with an html hook", :placeholder, { type: :text, animation: :glow },
    hook: :html, selector: "div.placeholder-glow"

  it_behaves_like "an element with an html hook", :placeholder, { type: :avatar },
    hook: :html, selector: "div.avatar.placeholder"

  it_behaves_like "an element with an html hook", :placeholder, { type: :image },
    hook: :html, selector: "div.ratio.placeholder"

  it_behaves_like "an element with an html hook", :placeholder, { type: :button },
    hook: :html, selector: "a.btn.placeholder"

  it_behaves_like "an element with an html hook", :placeholder, { type: :card },
    hook: :html, selector: "div.card"

  it_behaves_like "an element with an html hook", :placeholder, { type: :card },
    hook: :body_html, selector: "div.card-body"

  it_behaves_like "an element with an html hook", :placeholder, { type: :list, animation: :wave },
    hook: :html, selector: "div.placeholder-wave"

  it "appends a caller class on the button root instead of replacing it" do
    fragment = component_fragment(:placeholder, type: :button, html: { class: "hook-extra-class" })
    classes = fragment.css("a").first["class"].split(/\s+/)

    expect(classes).to include("btn", "disabled", "placeholder", "hook-extra-class")
  end

  # --- color: -------------------------------------------------------------

  it "renders btn-<color> on the button type when color: is given" do
    fragment = component_fragment(:placeholder, type: :button, color: "primary")

    expect(fragment.css("a").first["class"].split(/\s+/)).to include("btn-primary")
  end

  it "raises ArgumentError for an unknown color:" do
    expect { component_fragment(:placeholder, type: :button, color: "not-a-color") }
      .to raise_error(ArgumentError, /unknown color/)
  end

  it "ignores variant: -- it is not a recognized option any more" do
    fragment = component_fragment(:placeholder, type: :button, variant: "primary")
    classes = fragment.css("a").first["class"].split(/\s+/)

    expect(classes).not_to include("btn-primary")
    expect(classes.grep(/\Abtn-/)).to be_empty
  end

  # --- other options behave as before -------------------------------------

  it "renders one line per lines: entry, using each as a col width" do
    fragment = component_fragment(:placeholder, type: :text, lines: [10, 11, 8])
    lines = fragment.css("div.placeholder.placeholder-xs")

    expect(lines.map { |l| l["class"] }).to contain_exactly(
      "placeholder placeholder-xs col-10",
      "placeholder placeholder-xs col-11",
      "placeholder placeholder-xs col-8"
    )
  end

  it "applies placeholder-<animation> to the :text wrapper" do
    fragment = component_fragment(:placeholder, type: :text, animation: :glow)

    expect(fragment.css("div.placeholder-glow")).not_to be_empty
  end

  it "applies placeholder-<animation> to the :card wrapper" do
    fragment = component_fragment(:placeholder, type: :card, animation: :wave)

    expect(fragment.css("div.card.placeholder-wave")).not_to be_empty
  end

  it "defaults rounded: true on the avatar type" do
    fragment = component_fragment(:placeholder, type: :avatar)

    expect(fragment.css("div.avatar-rounded")).not_to be_empty
  end

  it "drops avatar-rounded when rounded: false" do
    fragment = component_fragment(:placeholder, type: :avatar, rounded: false)

    expect(fragment.css("div.avatar-rounded")).to be_empty
  end

  it "applies width: as col-<width> on the text placeholder" do
    fragment = component_fragment(:placeholder, type: :text, width: 6)

    expect(fragment.css("div.col-6")).not_to be_empty
  end

  it "applies size: as placeholder-<size> on the text placeholder" do
    fragment = component_fragment(:placeholder, type: :text, size: "lg")

    expect(fragment.css("div.placeholder-lg")).not_to be_empty
  end

  it "applies size: as avatar-<size> on the avatar placeholder" do
    fragment = component_fragment(:placeholder, type: :avatar, size: "sm")

    expect(fragment.css("div.avatar-sm")).not_to be_empty
  end

  it "uses ratio: for the image aspect ratio, falling back to 21x9" do
    fragment = component_fragment(:placeholder, type: :image, ratio: "4x3")
    expect(fragment.css("div.ratio-4x3")).not_to be_empty

    fragment = component_fragment(:placeholder, type: :image, ratio: "not-a-ratio")
    expect(fragment.css("div.ratio-21x9")).not_to be_empty
  end

  it "show_image: true (default) renders the card's image block" do
    fragment = component_fragment(:placeholder, type: :card)

    expect(fragment.css("div.card-img-top")).not_to be_empty
  end

  it "show_image: false omits the card's image block" do
    fragment = component_fragment(:placeholder, type: :card, show_image: false)

    expect(fragment.css("div.card-img-top")).to be_empty
  end

  it "show_button: true (default) renders the card's button block" do
    fragment = component_fragment(:placeholder, type: :card)

    expect(fragment.css("div.card-body a.btn")).not_to be_empty
  end

  it "show_button: false omits the card's button block" do
    fragment = component_fragment(:placeholder, type: :card, show_button: false)

    expect(fragment.css("div.card-body a.btn")).to be_empty
  end
end
