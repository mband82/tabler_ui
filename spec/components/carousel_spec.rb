# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Carousel", type: :component do
  it "renders with just the mandatory id" do
    fragment = component_fragment(:carousel, "my-carousel")

    expect(fragment.css(".carousel").first["id"]).to eq("my-carousel")
    expect(fragment.css(".carousel.slide")).not_to be_empty
    expect(fragment.css(".carousel-inner")).not_to be_empty
  end

  it "raises ArgumentError naming the component when id is missing" do
    expect { component_fragment(:carousel) }
      .to raise_error(ArgumentError, /tabler_ui\.carousel requires id/)
  end

  it "yields the component itself, in builder style" do
    expect(TablerUi::Carousel::Component.builder_style?).to be(true)

    yielded = nil
    component_fragment(:carousel, "my-carousel") do |carousel|
      yielded = carousel
    end

    expect(yielded).to be_a(TablerUi::Carousel::Component)
    expect(yielded).to respond_to(:item)
  end

  it 'sets data-controller="tabler-ui--carousel" on the root' do
    fragment = component_fragment(:carousel, "my-carousel")

    expect(fragment.css(".carousel").first["data-controller"]).to eq("tabler-ui--carousel")
  end

  it 'sets data-bs-ride="carousel" on the root, so autoplay works without extra JS config' do
    fragment = component_fragment(:carousel, "my-carousel")

    expect(fragment.css(".carousel").first["data-bs-ride"]).to eq("carousel")
  end

  describe "active slide validation" do
    it "raises ArgumentError when no slide is active" do
      expect do
        component_fragment(:carousel, "my-carousel") do |carousel|
          carousel.item(image: "a.jpg", active: false)
        end
      end.to raise_error(ArgumentError, /my-carousel.*exactly one active/)
    end

    it "raises ArgumentError when more than one slide is active" do
      expect do
        component_fragment(:carousel, "my-carousel") do |carousel|
          carousel.item(image: "a.jpg", active: true)
          carousel.item(image: "b.jpg", active: true)
        end
      end.to raise_error(ArgumentError, /my-carousel.*exactly one active/)
    end

    it "defaults a single slide to active when active: is not given" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg")
      end

      expect(fragment.css(".carousel-item").first["class"].split(/\s+/)).to include("active")
    end

    it "defaults the first of several slides to active when none is explicitly marked" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg")
        carousel.item(image: "b.jpg")
        carousel.item(image: "c.jpg")
      end

      items = fragment.css(".carousel-item")
      expect(items[0]["class"].split(/\s+/)).to include("active")
      expect(items[1]["class"].split(/\s+/)).not_to include("active")
      expect(items[2]["class"].split(/\s+/)).not_to include("active")
    end

    it "honours an explicit active: on a later slide" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg", active: false)
        carousel.item(image: "b.jpg", active: true)
      end

      items = fragment.css(".carousel-item")
      expect(items[0]["class"].split(/\s+/)).not_to include("active")
      expect(items[1]["class"].split(/\s+/)).to include("active")
    end
  end

  describe "indicators" do
    it "renders one indicator button per slide, with matching data-bs-slide-to indices" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg")
        carousel.item(image: "b.jpg")
        carousel.item(image: "c.jpg")
      end

      buttons = fragment.css(".carousel-indicators button")
      expect(buttons.map { |b| b["data-bs-slide-to"] }).to eq(%w[0 1 2])
      expect(buttons.map { |b| b["data-bs-target"] }).to eq(["#my-carousel"] * 3)
    end

    it "marks the active slide's indicator with class active and aria-current" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg", active: false)
        carousel.item(image: "b.jpg", active: true)
      end

      buttons = fragment.css(".carousel-indicators button")
      expect(buttons[0]["class"].to_s.split(/\s+/)).not_to include("active")
      expect(buttons[0]["aria-current"]).to be_nil
      expect(buttons[1]["class"].to_s.split(/\s+/)).to include("active")
      expect(buttons[1]["aria-current"]).to eq("true")
    end

    it "renders no indicators for indicators: false" do
      fragment = component_fragment(:carousel, "my-carousel", indicators: false) do |carousel|
        carousel.item(image: "a.jpg")
      end

      expect(fragment.css(".carousel-indicators")).to be_empty
    end

    it "renders plain carousel-indicators for the default (indicators: true)" do
      fragment = component_fragment(:carousel, "my-carousel")

      classes = fragment.css(".carousel-indicators").first["class"].split(/\s+/)
      expect(classes).to eq(["carousel-indicators"])
    end

    it "adds carousel-indicators-dot for indicators: :dot" do
      fragment = component_fragment(:carousel, "my-carousel", indicators: :dot)

      expect(fragment.css(".carousel-indicators").first["class"].split(/\s+/)).to include("carousel-indicators-dot")
    end

    it "adds carousel-indicators-thumb for indicators: :thumb, with a background-image style from image:" do
      fragment = component_fragment(:carousel, "my-carousel", indicators: :thumb) do |carousel|
        carousel.item(image: "a.jpg")
      end

      indicators = fragment.css(".carousel-indicators").first
      expect(indicators["class"].split(/\s+/)).to include("carousel-indicators-thumb")

      button = fragment.css(".carousel-indicators button").first
      expect(button["style"]).to eq("background-image: url(a.jpg)")
    end

    it "adds carousel-indicators-vertical for indicators: :vertical" do
      fragment = component_fragment(:carousel, "my-carousel", indicators: :vertical)

      expect(fragment.css(".carousel-indicators").first["class"].split(/\s+/)).to include("carousel-indicators-vertical")
    end

    it "raises ArgumentError naming carousel for an unknown indicators: value" do
      expect { component_fragment(:carousel, "my-carousel", indicators: :bogus) }
        .to raise_error(ArgumentError, /bogus/)
      expect { component_fragment(:carousel, "my-carousel", indicators: :bogus) }
        .to raise_error(ArgumentError, /carousel/)
    end
  end

  describe "controls" do
    it "renders prev/next controls with accessible names by default" do
      fragment = component_fragment(:carousel, "my-carousel")

      prev = fragment.css(".carousel-control-prev").first
      nxt = fragment.css(".carousel-control-next").first

      expect(prev).not_to be_nil
      expect(nxt).not_to be_nil
      expect(prev.css(".visually-hidden").text).to eq("Previous")
      expect(nxt.css(".visually-hidden").text).to eq("Next")
      expect(prev["data-bs-target"]).to eq("#my-carousel")
      expect(prev["data-bs-slide"]).to eq("prev")
      expect(nxt["data-bs-slide"]).to eq("next")
    end

    it "renders no controls for controls: false" do
      fragment = component_fragment(:carousel, "my-carousel", controls: false)

      expect(fragment.css(".carousel-control-prev")).to be_empty
      expect(fragment.css(".carousel-control-next")).to be_empty
    end
  end

  describe "fade:" do
    it "adds carousel-fade" do
      fragment = component_fragment(:carousel, "my-carousel", fade: true)

      expect(fragment.css(".carousel").first["class"].split(/\s+/)).to include("carousel-fade")
    end

    it "omits carousel-fade by default" do
      fragment = component_fragment(:carousel, "my-carousel")

      expect(fragment.css(".carousel").first["class"].split(/\s+/)).not_to include("carousel-fade")
    end
  end

  describe "interval: / wrap: / keyboard:" do
    it "sets data-bs-interval when interval: is given, including false" do
      fragment = component_fragment(:carousel, "my-carousel", interval: 3000)
      expect(fragment.css(".carousel").first["data-bs-interval"]).to eq("3000")

      fragment = component_fragment(:carousel, "my-carousel", interval: false)
      expect(fragment.css(".carousel").first["data-bs-interval"]).to eq("false")
    end

    it "sets no data-bs-interval when interval: is not given" do
      fragment = component_fragment(:carousel, "my-carousel")
      expect(fragment.css(".carousel").first["data-bs-interval"]).to be_nil
    end

    it "sets data-bs-wrap when wrap: is given" do
      fragment = component_fragment(:carousel, "my-carousel", wrap: false)
      expect(fragment.css(".carousel").first["data-bs-wrap"]).to eq("false")
    end

    it "sets no data-bs-wrap when wrap: is not given" do
      fragment = component_fragment(:carousel, "my-carousel")
      expect(fragment.css(".carousel").first["data-bs-wrap"]).to be_nil
    end

    it "sets data-bs-keyboard when keyboard: is given" do
      fragment = component_fragment(:carousel, "my-carousel", keyboard: false)
      expect(fragment.css(".carousel").first["data-bs-keyboard"]).to eq("false")
    end

    it "sets no data-bs-keyboard when keyboard: is not given" do
      fragment = component_fragment(:carousel, "my-carousel")
      expect(fragment.css(".carousel").first["data-bs-keyboard"]).to be_nil
    end
  end

  describe "slide content" do
    it "renders image: as a d-block w-100 img" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg")
      end

      img = fragment.css(".carousel-item img").first
      expect(img).not_to be_nil
      expect(img["src"]).to eq("a.jpg")
      expect(img["class"].split(/\s+/)).to include("d-block", "w-100")
    end

    it "renders a block as the slide's content instead of image:" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "ignored.jpg") { "Custom slide content".html_safe }
      end

      item = fragment.css(".carousel-item").first
      expect(item.text).to include("Custom slide content")
      expect(item.css("img")).to be_empty
    end
  end

  describe "caption:" do
    it "renders caption: inside a .carousel-caption" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg", caption: "Look at this")
      end

      expect(fragment.css(".carousel-caption").text.strip).to eq("Look at this")
    end

    it "renders no .carousel-caption when caption: is absent" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg")
      end

      expect(fragment.css(".carousel-caption")).to be_empty
    end

    it "adds carousel-caption-background for caption_background: true" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg", caption: "Look at this", caption_background: true)
      end

      expect(fragment.css(".carousel-caption").first["class"].split(/\s+/)).to include("carousel-caption-background")
    end
  end

  it_behaves_like "an element with an html hook", :carousel, { id: "my-carousel" },
    hook: :html, selector: ".carousel"

  it_behaves_like "an element with an html hook", :carousel, { id: "my-carousel" },
    hook: :inner_html, selector: ".carousel-inner"

  it_behaves_like "an element with an html hook", :carousel, { id: "my-carousel" },
    hook: :indicators_html, selector: ".carousel-indicators"

  it_behaves_like "an element with an html hook", :carousel, { id: "my-carousel" },
    hook: :prev_html, selector: ".carousel-control-prev"

  it_behaves_like "an element with an html hook", :carousel, { id: "my-carousel" },
    hook: :next_html, selector: ".carousel-control-next"

  it "applies per-item html: to that slide only, via a plain Hash" do
    fragment = component_fragment(:carousel, "my-carousel") do |carousel|
      carousel.item(image: "a.jpg", active: false, html: { class: "hook-extra-class", id: "hook-test-id" })
      carousel.item(image: "b.jpg", active: true)
    end

    items = fragment.css(".carousel-item")
    expect(items[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(items[0]["id"]).to eq("hook-test-id")
    expect(items[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
  end

  it "applies per-item html: to that slide only, via a callable taking the item" do
    fragment = component_fragment(:carousel, "my-carousel") do |carousel|
      carousel.item(image: "a.jpg", active: false, html: ->(item) { { class: "callable-class-#{item.index}" } })
      carousel.item(image: "b.jpg", active: true, html: ->(item) { { class: "callable-class-#{item.index}" } })
    end

    items = fragment.css(".carousel-item")
    expect(items[0]["class"].split(/\s+/)).to include("callable-class-0")
    expect(items[0]["class"].split(/\s+/)).not_to include("callable-class-1")
    expect(items[1]["class"].split(/\s+/)).to include("callable-class-1")
  end

  it "applies per-item caption_html: to that slide's caption only" do
    fragment = component_fragment(:carousel, "my-carousel") do |carousel|
      carousel.item(image: "a.jpg", caption: "First", caption_html: { class: "hook-extra-class", id: "hook-test-id" })
    end

    caption = fragment.css(".carousel-caption").first
    expect(caption["class"].split(/\s+/)).to include("hook-extra-class", "carousel-caption")
    expect(caption["id"]).to eq("hook-test-id")
  end

  describe "accessibility" do
    it "sets role and aria-roledescription on the root" do
      fragment = component_fragment(:carousel, "my-carousel")
      root = fragment.css(".carousel").first

      expect(root["role"]).to eq("region")
      expect(root["aria-roledescription"]).to eq("carousel")
      expect(root["aria-label"]).to eq("Carousel")
    end

    it "sets role, aria-roledescription and a translated label on each slide" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg")
        carousel.item(image: "b.jpg")
      end

      items = fragment.css(".carousel-item")
      expect(items[0]["role"]).to eq("group")
      expect(items[0]["aria-roledescription"]).to eq("slide")
      expect(items[0]["aria-label"]).to eq("Slide 1 of 2")
      expect(items[1]["aria-label"]).to eq("Slide 2 of 2")
    end

    it "sets a translated aria-label per indicator button" do
      fragment = component_fragment(:carousel, "my-carousel") do |carousel|
        carousel.item(image: "a.jpg")
        carousel.item(image: "b.jpg")
      end

      buttons = fragment.css(".carousel-indicators button")
      expect(buttons[0]["aria-label"]).to eq("Slide 1")
      expect(buttons[1]["aria-label"]).to eq("Slide 2")
    end
  end
end
