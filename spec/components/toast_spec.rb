# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Toast", type: :component do
  it "renders with no arguments" do
    fragment = component_fragment(:toast)

    expect(fragment.css(".toast")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :toast, {},
    hook: :html, selector: ".toast"

  it_behaves_like "an element with an html hook", :toast, { title: "Saved" },
    hook: :header_html, selector: ".toast-header"

  it "passes id/data/class through body_html: onto the .toast-body" do
    fragment = component_fragment(:toast, body_html: { class: "hook-extra-class", id: "hook-test-id",
                                                         data: { testid: "hook-test-data" } }) do |slots|
      slots.body { "Content" }
    end
    element = fragment.css(".toast-body").first

    expect(element).not_to be_nil
    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("toast-body", "hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it_behaves_like "an element with an html hook", :toast, { position: "top-right" },
    hook: :container_html, selector: ".toast-container"

  it "adds toast-<color> for color:" do
    fragment = component_fragment(:toast, color: "success")

    expect(fragment.css(".toast").first["class"].split(/\s+/)).to include("toast-success")
  end

  it "supports the Tabler palette as well as the semantic colours" do
    fragment = component_fragment(:toast, color: "azure")

    expect(fragment.css(".toast").first["class"].split(/\s+/)).to include("toast-azure")
  end

  it "raises ArgumentError naming toast for an unknown colour" do
    expect { component_fragment(:toast, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:toast, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /toast/)
  end

  it "renders title: as a strong.me-auto inside the header when no header slot is given" do
    fragment = component_fragment(:toast, title: "Saved")

    expect(fragment.css(".toast-header strong.me-auto").text).to eq("Saved")
  end

  it "prefers a header slot over title: when both are given" do
    fragment = component_fragment(:toast, title: "Ignored title") do |slots|
      slots.header { "Custom header".html_safe }
    end

    expect(fragment.css(".toast-header").text).to include("Custom header")
    expect(fragment.css(".toast-header strong.me-auto")).to be_empty
    expect(fragment.to_html).not_to include("Ignored title")
  end

  it "renders the body slot's content" do
    fragment = component_fragment(:toast) do |slots|
      slots.body { "Body content" }
    end

    expect(fragment.css(".toast-body").text.strip).to eq("Body content")
  end

  it "renders no .toast-body wrapper when the body slot is omitted" do
    fragment = component_fragment(:toast, title: "Saved")

    expect(fragment.css(".toast-body")).to be_empty
  end

  it "renders no .toast-header when there is no title, no header slot and close_button: false" do
    fragment = component_fragment(:toast, close_button: false) do |slots|
      slots.body { "Body content" }
    end

    expect(fragment.css(".toast-header")).to be_empty
  end

  describe "autohide: / delay:" do
    it "sets data-bs-autohide when autohide: is given" do
      fragment = component_fragment(:toast, autohide: false)

      expect(fragment.css(".toast").first["data-bs-autohide"]).to eq("false")
    end

    it "sets no data-bs-autohide when autohide: is not given" do
      fragment = component_fragment(:toast)

      expect(fragment.css(".toast").first["data-bs-autohide"]).to be_nil
    end

    it "sets data-bs-delay when delay: is given" do
      fragment = component_fragment(:toast, delay: 8000)

      expect(fragment.css(".toast").first["data-bs-delay"]).to eq("8000")
    end

    it "sets no data-bs-delay when delay: is not given" do
      fragment = component_fragment(:toast)

      expect(fragment.css(".toast").first["data-bs-delay"]).to be_nil
    end
  end

  describe "position:" do
    it "renders no .toast-container when position: is absent" do
      fragment = component_fragment(:toast)

      expect(fragment.css(".toast-container")).to be_empty
      expect(fragment.css(".toast")).not_to be_empty
    end

    it "wraps the toast in a positioned .toast-container for position:" do
      fragment = component_fragment(:toast, position: "top-right")
      container = fragment.css(".toast-container").first

      expect(container).not_to be_nil
      classes = container["class"].split(/\s+/)
      expect(classes).to include("toast-container", "position-fixed", "top-0", "end-0")
      expect(fragment.css(".toast-container > .toast")).not_to be_empty
    end

    it "maps each of the nine placements to the right utility classes" do
      expectations = {
        "top-left" => %w[top-0 start-0],
        "top-center" => %w[top-0 start-50 translate-middle-x],
        "top-right" => %w[top-0 end-0],
        "middle-left" => %w[top-50 start-0 translate-middle-y],
        "middle-center" => %w[top-50 start-50 translate-middle],
        "middle-right" => %w[top-50 end-0 translate-middle-y],
        "bottom-left" => %w[bottom-0 start-0],
        "bottom-center" => %w[bottom-0 start-50 translate-middle-x],
        "bottom-right" => %w[bottom-0 end-0]
      }

      expectations.each do |position, expected_classes|
        fragment = component_fragment(:toast, position: position)
        classes = fragment.css(".toast-container").first["class"].split(/\s+/)

        expect(classes).to include(*expected_classes)
      end
    end

    it "raises ArgumentError naming toast for an unknown position" do
      expect { component_fragment(:toast, position: "not-a-real-position") }
        .to raise_error(ArgumentError, /not-a-real-position/)
      expect { component_fragment(:toast, position: "not-a-real-position") }
        .to raise_error(ArgumentError, /toast/)
    end
  end

  it 'sets data-controller="tabler-ui--toast" on the .toast element, not a trigger' do
    fragment = component_fragment(:toast, position: "top-right")

    expect(fragment.css(".toast").first["data-controller"]).to eq("tabler-ui--toast")
    expect(fragment.css(".toast-container").first["data-controller"]).to be_nil
  end

  describe "accessibility" do
    it "sets role=alert, aria-live=assertive and aria-atomic=true on the root by default" do
      fragment = component_fragment(:toast)
      element = fragment.css(".toast").first

      expect(element["role"]).to eq("alert")
      expect(element["aria-live"]).to eq("assertive")
      expect(element["aria-atomic"]).to eq("true")
    end

    it "renders a .btn-close with a translated aria-label by default" do
      fragment = component_fragment(:toast, title: "Saved")
      button = fragment.css(".btn-close").first

      expect(button).not_to be_nil
      expect(button["aria-label"]).to eq("Close")
      expect(button["data-bs-dismiss"]).to eq("toast")
    end

    it "suppresses the .btn-close for close_button: false" do
      fragment = component_fragment(:toast, title: "Saved", close_button: false)

      expect(fragment.css(".btn-close")).to be_empty
    end
  end
end
