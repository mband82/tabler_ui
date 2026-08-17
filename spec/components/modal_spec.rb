# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Modal", type: :component do
  it "renders with just the mandatory id" do
    fragment = component_fragment(:modal, "my-modal")

    expect(fragment.css(".modal").first["id"]).to eq("my-modal")
  end

  it "raises ArgumentError naming the component when id is missing" do
    expect { component_fragment(:modal) }
      .to raise_error(ArgumentError, /modal/)
  end

  it_behaves_like "an element with an html hook", :modal, { id: "my-modal" },
    hook: :html, selector: ".modal"

  it_behaves_like "an element with an html hook", :modal, { id: "my-modal" },
    hook: :dialog_html, selector: ".modal-dialog"

  it_behaves_like "an element with an html hook", :modal, { id: "my-modal" },
    hook: :content_html, selector: ".modal-content"

  it_behaves_like "an element with an html hook", :modal, { id: "my-modal", title: "Confirm" },
    hook: :header_html, selector: ".modal-header"

  it "passes id/data/class through body_html: onto the .modal-body" do
    fragment = component_fragment(:modal, "my-modal", body_html: { class: "hook-extra-class", id: "hook-test-id",
                                                                     data: { testid: "hook-test-data" } }) do |slots|
      slots.body { "Content" }
    end
    element = fragment.css(".modal-body").first

    expect(element).not_to be_nil
    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("modal-body", "hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it "passes id/data/class through footer_html: onto the .modal-footer" do
    fragment = component_fragment(:modal, "my-modal", footer_html: { class: "hook-extra-class", id: "hook-test-id",
                                                                       data: { testid: "hook-test-data" } }) do |slots|
      slots.footer { "Content" }
    end
    element = fragment.css(".modal-footer").first

    expect(element).not_to be_nil
    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("modal-footer", "hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it "renders the required .modal > .modal-dialog > .modal-content nesting" do
    fragment = component_fragment(:modal, "my-modal")

    expect(fragment.css(".modal > .modal-dialog > .modal-content")).not_to be_empty
  end

  it "adds modal-<size> for size:" do
    fragment = component_fragment(:modal, "my-modal", size: "lg")

    expect(fragment.css(".modal-dialog").first["class"].split(/\s+/)).to include("modal-lg")
  end

  it "adds modal-fullscreen (not modal-modal-fullscreen) for size: fullscreen" do
    fragment = component_fragment(:modal, "my-modal", size: "fullscreen")
    classes = fragment.css(".modal-dialog").first["class"].split(/\s+/)

    expect(classes).to include("modal-fullscreen")
    expect(classes).not_to include("modal-modal-fullscreen")
  end

  it "raises ArgumentError naming modal for an unknown size" do
    expect { component_fragment(:modal, "my-modal", size: "not-a-real-size") }
      .to raise_error(ArgumentError, /not-a-real-size/)
    expect { component_fragment(:modal, "my-modal", size: "not-a-real-size") }
      .to raise_error(ArgumentError, /modal/)
  end

  it "adds modal-dialog-centered for centered: true" do
    fragment = component_fragment(:modal, "my-modal", centered: true)

    expect(fragment.css(".modal-dialog").first["class"].split(/\s+/)).to include("modal-dialog-centered")
  end

  it "adds modal-dialog-scrollable for scrollable: true" do
    fragment = component_fragment(:modal, "my-modal", scrollable: true)

    expect(fragment.css(".modal-dialog").first["class"].split(/\s+/)).to include("modal-dialog-scrollable")
  end

  it "adds modal-blur on the root .modal for blur: true" do
    fragment = component_fragment(:modal, "my-modal", blur: true)

    expect(fragment.css(".modal").first["class"].split(/\s+/)).to include("modal-blur")
  end

  it "adds a modal-status strip with the color's bg class for status:" do
    fragment = component_fragment(:modal, "my-modal", status: "red")

    expect(fragment.css(".modal-content > .modal-status.bg-red")).not_to be_empty
  end

  it "renders no modal-status strip when status: is absent" do
    fragment = component_fragment(:modal, "my-modal")

    expect(fragment.css(".modal-status")).to be_empty
  end

  it "raises ArgumentError naming modal for an unknown status color" do
    expect { component_fragment(:modal, "my-modal", status: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:modal, "my-modal", status: "not-a-real-color") }
      .to raise_error(ArgumentError, /modal/)
  end

  it "renders the header, body and footer slots' content" do
    fragment = component_fragment(:modal, "my-modal") do |slots|
      slots.header { "Header content" }
      slots.body { "Body content" }
      slots.footer { "Footer content" }
    end

    expect(fragment.css(".modal-header").text).to include("Header content")
    expect(fragment.css(".modal-body").text.strip).to eq("Body content")
    expect(fragment.css(".modal-footer").text.strip).to eq("Footer content")
  end

  it "renders no header/body/footer wrapper when the corresponding slot is omitted and no title:" do
    fragment = component_fragment(:modal, "my-modal") do |slots|
      slots.body { "Body content" }
    end

    expect(fragment.css(".modal-header")).to be_empty
    expect(fragment.css(".modal-body")).not_to be_empty
    expect(fragment.css(".modal-footer")).to be_empty
  end

  it "renders title: as an h5.modal-title inside the header when no header slot is given" do
    fragment = component_fragment(:modal, "my-modal", title: "Confirm")

    expect(fragment.css(".modal-header h5.modal-title").text).to eq("Confirm")
  end

  it "prefers a header slot over title: when both are given" do
    fragment = component_fragment(:modal, "my-modal", title: "Ignored title") do |slots|
      slots.header { "Custom header".html_safe }
    end

    expect(fragment.css(".modal-header").text.strip).to eq("Custom header")
    expect(fragment.css(".modal-header h5.modal-title")).to be_empty
    expect(fragment.to_html).not_to include("Ignored title")
  end

  it 'sets data-controller="tabler-ui--modal" on the root' do
    fragment = component_fragment(:modal, "my-modal")

    expect(fragment.css(".modal").first["data-controller"]).to eq("tabler-ui--modal")
  end

  describe "accessibility" do
    it "sets tabindex and role on the root" do
      fragment = component_fragment(:modal, "my-modal")
      element = fragment.css(".modal").first

      expect(element["tabindex"]).to eq("-1")
      expect(element["role"]).to eq("dialog")
    end

    it "sets aria-labelledby pointing at the rendered .modal-title when title: is given" do
      fragment = component_fragment(:modal, "my-modal", title: "Confirm")
      root = fragment.css(".modal").first
      title = fragment.css(".modal-title").first

      expect(root["aria-labelledby"]).to eq(title["id"])
      expect(root["aria-label"]).to be_nil
    end

    it "sets a translated aria-label when there is no title:" do
      fragment = component_fragment(:modal, "my-modal")
      root = fragment.css(".modal").first

      expect(root["aria-label"]).to eq("Dialog")
      expect(root["aria-labelledby"]).to be_nil
    end

    it "sets a translated aria-label when a header slot overrides title:" do
      fragment = component_fragment(:modal, "my-modal", title: "Ignored") do |slots|
        slots.header { "Custom header" }
      end
      root = fragment.css(".modal").first

      expect(root["aria-label"]).to eq("Dialog")
      expect(root["aria-labelledby"]).to be_nil
    end

    it "renders a .btn-close with a translated aria-label by default" do
      fragment = component_fragment(:modal, "my-modal")
      button = fragment.css(".btn-close").first

      expect(button).not_to be_nil
      expect(button["aria-label"]).to eq("Close")
      expect(button["data-bs-dismiss"]).to eq("modal")
    end

    it "suppresses the .btn-close for close_button: false" do
      fragment = component_fragment(:modal, "my-modal", close_button: false)

      expect(fragment.css(".btn-close")).to be_empty
    end
  end
end
