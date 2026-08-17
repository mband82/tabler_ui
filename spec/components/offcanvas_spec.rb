# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Offcanvas", type: :component do
  it "renders with just the mandatory id" do
    fragment = component_fragment(:offcanvas, "my-offcanvas")

    expect(fragment.css(".offcanvas").first["id"]).to eq("my-offcanvas")
  end

  it "raises ArgumentError naming the component when id is missing" do
    expect { component_fragment(:offcanvas) }
      .to raise_error(ArgumentError, /offcanvas/)
  end

  it_behaves_like "an element with an html hook", :offcanvas, { id: "my-offcanvas" },
    hook: :html, selector: ".offcanvas"

  it_behaves_like "an element with an html hook", :offcanvas, { id: "my-offcanvas", title: "Filters" },
    hook: :header_html, selector: ".offcanvas-header"

  it "passes id/data/class through body_html: onto the .offcanvas-body" do
    fragment = component_fragment(:offcanvas, "my-offcanvas", body_html: { class: "hook-extra-class", id: "hook-test-id",
                                                                             data: { testid: "hook-test-data" } }) do |slots|
      slots.body { "Content" }
    end
    element = fragment.css(".offcanvas-body").first

    expect(element).not_to be_nil
    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("offcanvas-body", "hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it "passes id/data/class through footer_html: onto the .offcanvas-footer" do
    fragment = component_fragment(:offcanvas, "my-offcanvas", footer_html: { class: "hook-extra-class", id: "hook-test-id",
                                                                               data: { testid: "hook-test-data" } }) do |slots|
      slots.footer { "Content" }
    end
    element = fragment.css(".offcanvas-footer").first

    expect(element).not_to be_nil
    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("offcanvas-footer", "hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  describe "position:" do
    %w[start end top bottom].each do |edge|
      it "adds offcanvas-#{edge} for position: #{edge.inspect}" do
        fragment = component_fragment(:offcanvas, "my-offcanvas", position: edge)

        expect(fragment.css(".offcanvas").first["class"].split(/\s+/)).to include("offcanvas-#{edge}")
      end
    end

    it "defaults to offcanvas-start when position: is omitted" do
      fragment = component_fragment(:offcanvas, "my-offcanvas")

      expect(fragment.css(".offcanvas").first["class"].split(/\s+/)).to include("offcanvas-start")
    end

    it "raises ArgumentError naming offcanvas for an unknown position" do
      expect { component_fragment(:offcanvas, "my-offcanvas", position: "not-a-real-edge") }
        .to raise_error(ArgumentError, /not-a-real-edge/)
      expect { component_fragment(:offcanvas, "my-offcanvas", position: "not-a-real-edge") }
        .to raise_error(ArgumentError, /offcanvas/)
    end
  end

  it "adds offcanvas-narrow for narrow: true" do
    fragment = component_fragment(:offcanvas, "my-offcanvas", narrow: true)

    expect(fragment.css(".offcanvas").first["class"].split(/\s+/)).to include("offcanvas-narrow")
  end

  it "renders no offcanvas-narrow by default" do
    fragment = component_fragment(:offcanvas, "my-offcanvas")

    expect(fragment.css(".offcanvas").first["class"].split(/\s+/)).not_to include("offcanvas-narrow")
  end

  describe "expand:" do
    it "renders the bare offcanvas class and no offcanvas-<bp> class by default" do
      fragment = component_fragment(:offcanvas, "my-offcanvas")
      classes = fragment.css(".offcanvas").first["class"].split(/\s+/)

      expect(classes).to include("offcanvas")
      expect(classes.grep(/\Aoffcanvas-(sm|md|lg|xl|xxl)\z/)).to be_empty
    end

    %w[sm md lg xl xxl].each do |breakpoint|
      it "swaps the bare offcanvas class for offcanvas-#{breakpoint} and keeps the edge class" do
        fragment = component_fragment(:offcanvas, "my-offcanvas", expand: breakpoint)
        element = fragment.css(".offcanvas-#{breakpoint}").first
        classes = element["class"].split(/\s+/)

        expect(classes).to include("offcanvas-#{breakpoint}", "offcanvas-start")
        expect(classes).not_to include("offcanvas")
      end
    end

    it "combines with narrow:" do
      fragment = component_fragment(:offcanvas, "my-offcanvas", expand: "lg", narrow: true)
      classes = fragment.css(".offcanvas-lg").first["class"].split(/\s+/)

      expect(classes).to include("offcanvas-lg", "offcanvas-start", "offcanvas-narrow")
    end

    it "raises ArgumentError naming offcanvas for an unknown breakpoint" do
      expect { component_fragment(:offcanvas, "my-offcanvas", expand: "not-a-real-breakpoint") }
        .to raise_error(ArgumentError, /not-a-real-breakpoint/)
      expect { component_fragment(:offcanvas, "my-offcanvas", expand: "not-a-real-breakpoint") }
        .to raise_error(ArgumentError, /offcanvas/)
    end

    it "leaves data-bs-* attributes unchanged" do
      without_expand = component_fragment(:offcanvas, "my-offcanvas", backdrop: :static, scroll: true)
      with_expand = component_fragment(:offcanvas, "my-offcanvas", backdrop: :static, scroll: true, expand: "lg")

      root_without = without_expand.css(".offcanvas").first
      root_with = with_expand.css(".offcanvas-lg").first

      expect(root_with["data-bs-backdrop"]).to eq(root_without["data-bs-backdrop"])
      expect(root_with["data-bs-scroll"]).to eq(root_without["data-bs-scroll"])
      expect(root_with["data-controller"]).to eq(root_without["data-controller"])
    end
  end

  describe "backdrop:" do
    it "renders no data-bs-backdrop by default" do
      fragment = component_fragment(:offcanvas, "my-offcanvas")

      expect(fragment.css(".offcanvas").first["data-bs-backdrop"]).to be_nil
    end

    it 'sets data-bs-backdrop="false" for backdrop: false' do
      fragment = component_fragment(:offcanvas, "my-offcanvas", backdrop: false)

      expect(fragment.css(".offcanvas").first["data-bs-backdrop"]).to eq("false")
    end

    it 'sets data-bs-backdrop="static" for backdrop: :static' do
      fragment = component_fragment(:offcanvas, "my-offcanvas", backdrop: :static)

      expect(fragment.css(".offcanvas").first["data-bs-backdrop"]).to eq("static")
    end
  end

  describe "scroll:" do
    it "renders no data-bs-scroll by default" do
      fragment = component_fragment(:offcanvas, "my-offcanvas")

      expect(fragment.css(".offcanvas").first["data-bs-scroll"]).to be_nil
    end

    it 'sets data-bs-scroll="true" for scroll: true' do
      fragment = component_fragment(:offcanvas, "my-offcanvas", scroll: true)

      expect(fragment.css(".offcanvas").first["data-bs-scroll"]).to eq("true")
    end
  end

  it "renders the header, body and footer slots' content" do
    fragment = component_fragment(:offcanvas, "my-offcanvas") do |slots|
      slots.header { "Header content" }
      slots.body { "Body content" }
      slots.footer { "Footer content" }
    end

    expect(fragment.css(".offcanvas-header").text).to include("Header content")
    expect(fragment.css(".offcanvas-body").text.strip).to eq("Body content")
    expect(fragment.css(".offcanvas-footer").text.strip).to eq("Footer content")
  end

  it "renders no header/body/footer wrapper when the corresponding slot is omitted, no title:, and close_button: false" do
    fragment = component_fragment(:offcanvas, "my-offcanvas", close_button: false) do |slots|
      slots.body { "Body content" }
    end

    expect(fragment.css(".offcanvas-header")).to be_empty
    expect(fragment.css(".offcanvas-body")).not_to be_empty
    expect(fragment.css(".offcanvas-footer")).to be_empty
  end

  it "still renders an .offcanvas-header to host the default close button when no title/header slot is given" do
    fragment = component_fragment(:offcanvas, "my-offcanvas")

    expect(fragment.css(".offcanvas-header")).not_to be_empty
    expect(fragment.css(".offcanvas-header .btn-close")).not_to be_empty
  end

  it "renders title: as an h5.offcanvas-title inside the header when no header slot is given" do
    fragment = component_fragment(:offcanvas, "my-offcanvas", title: "Filters")

    expect(fragment.css(".offcanvas-header h5.offcanvas-title").text).to eq("Filters")
  end

  it "prefers a header slot over title: when both are given" do
    fragment = component_fragment(:offcanvas, "my-offcanvas", title: "Ignored title") do |slots|
      slots.header { "Custom header".html_safe }
    end

    expect(fragment.css(".offcanvas-header").text.strip).to eq("Custom header")
    expect(fragment.css(".offcanvas-header h5.offcanvas-title")).to be_empty
    expect(fragment.to_html).not_to include("Ignored title")
  end

  it "does not render the built-in close button when a header slot is given" do
    fragment = component_fragment(:offcanvas, "my-offcanvas") do |slots|
      slots.header { "Custom header" }
    end

    expect(fragment.css(".offcanvas-header .btn-close")).to be_empty
  end

  it 'sets data-controller="tabler-ui--offcanvas" on the root' do
    fragment = component_fragment(:offcanvas, "my-offcanvas")

    expect(fragment.css(".offcanvas").first["data-controller"]).to eq("tabler-ui--offcanvas")
  end

  describe "accessibility" do
    it "sets tabindex and role on the root" do
      fragment = component_fragment(:offcanvas, "my-offcanvas")
      element = fragment.css(".offcanvas").first

      expect(element["tabindex"]).to eq("-1")
      expect(element["role"]).to eq("dialog")
    end

    it "sets aria-labelledby pointing at the rendered .offcanvas-title when title: is given" do
      fragment = component_fragment(:offcanvas, "my-offcanvas", title: "Filters")
      root = fragment.css(".offcanvas").first
      title = fragment.css(".offcanvas-title").first

      expect(root["aria-labelledby"]).to eq(title["id"])
      expect(root["aria-label"]).to be_nil
    end

    it "sets a translated aria-label when there is no title:" do
      fragment = component_fragment(:offcanvas, "my-offcanvas")
      root = fragment.css(".offcanvas").first

      expect(root["aria-label"]).to eq("Dialog")
      expect(root["aria-labelledby"]).to be_nil
    end

    it "sets a translated aria-label when a header slot overrides title:" do
      fragment = component_fragment(:offcanvas, "my-offcanvas", title: "Ignored") do |slots|
        slots.header { "Custom header" }
      end
      root = fragment.css(".offcanvas").first

      expect(root["aria-label"]).to eq("Dialog")
      expect(root["aria-labelledby"]).to be_nil
    end

    it "renders a .btn-close with a translated aria-label by default" do
      fragment = component_fragment(:offcanvas, "my-offcanvas")
      button = fragment.css(".btn-close").first

      expect(button).not_to be_nil
      expect(button["aria-label"]).to eq("Close")
      expect(button["data-bs-dismiss"]).to eq("offcanvas")
    end

    it "suppresses the .btn-close for close_button: false" do
      fragment = component_fragment(:offcanvas, "my-offcanvas", close_button: false)

      expect(fragment.css(".btn-close")).to be_empty
    end
  end
end
