# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Progress", type: :component do
  it "renders with no arguments at all (percent defaults to 0)" do
    fragment = component_fragment(:progress)
    bar = fragment.css(".progress-bar").first

    expect(fragment.css(".progress")).not_to be_empty
    expect(bar).not_to be_nil
    expect(bar["style"]).to include("width: 0.0%")
  end

  it_behaves_like "an element with an html hook", :progress, {},
    hook: :html, selector: ".progress"

  it_behaves_like "an element with an html hook", :progress, {},
    hook: :bar_html, selector: ".progress-bar"

  it_behaves_like "an element with an html hook", :progress, { label: "Uploading" },
    hook: :label_html, selector: ".d-flex"

  it "clamps percent above 100" do
    fragment = component_fragment(:progress, percent: 150)
    bar = fragment.css(".progress-bar").first

    expect(bar["style"]).to include("width: 100.0%")
    expect(bar["aria-valuenow"]).to eq("100.0")
  end

  it "clamps percent below 0" do
    fragment = component_fragment(:progress, percent: -20)
    bar = fragment.css(".progress-bar").first

    expect(bar["style"]).to include("width: 0.0%")
    expect(bar["aria-valuenow"]).to eq("0.0")
  end

  describe "color: \"auto\"" do
    it "picks danger at and above the 90 threshold" do
      fragment = component_fragment(:progress, percent: 90, color: "auto")
      expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("bg-danger")

      fragment = component_fragment(:progress, percent: 100, color: "auto")
      expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("bg-danger")
    end

    it "picks warning between the 75 and 90 thresholds" do
      fragment = component_fragment(:progress, percent: 75, color: "auto")
      expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("bg-warning")

      fragment = component_fragment(:progress, percent: 89, color: "auto")
      expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("bg-warning")
    end

    it "picks success below the 75 threshold" do
      fragment = component_fragment(:progress, percent: 0, color: "auto")
      expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("bg-success")

      fragment = component_fragment(:progress, percent: 74, color: "auto")
      expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("bg-success")
    end

    it "does not raise for the \"auto\" magic value" do
      expect { component_fragment(:progress, percent: 50, color: "auto") }.not_to raise_error
    end
  end

  it "raises ArgumentError naming progress for an unknown color" do
    expect { component_fragment(:progress, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /not-a-real-color/)
    expect { component_fragment(:progress, color: "not-a-real-color") }
      .to raise_error(ArgumentError, /progress/)
  end

  it "accepts a Tabler palette color" do
    fragment = component_fragment(:progress, color: "blue")
    expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("bg-blue")
  end

  it "accepts a Bootstrap semantic color" do
    fragment = component_fragment(:progress, color: "danger")
    expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("bg-danger")
  end

  it "defaults to primary when no color is given" do
    fragment = component_fragment(:progress, percent: 42)
    expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("bg-primary")
  end

  it "adds progress-bar-striped for striped: true" do
    fragment = component_fragment(:progress, striped: true)
    expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("progress-bar-striped")
  end

  it "adds progress-bar-animated for animated: true" do
    fragment = component_fragment(:progress, animated: true)
    expect(fragment.css(".progress-bar").first["class"].split(/\s+/)).to include("progress-bar-animated")
  end

  it "does not add striped/animated classes by default" do
    fragment = component_fragment(:progress)
    classes = fragment.css(".progress-bar").first["class"].split(/\s+/)

    expect(classes).not_to include("progress-bar-striped")
    expect(classes).not_to include("progress-bar-animated")
  end

  it "adds progress-<size> for size:" do
    fragment = component_fragment(:progress, size: :sm)
    expect(fragment.css(".progress").first["class"].split(/\s+/)).to include("progress-sm")
  end

  it "sets height: on the outer element for height:" do
    fragment = component_fragment(:progress, height: "4px")
    expect(fragment.css(".progress").first["style"]).to include("height: 4px;")
  end

  describe "label row" do
    it "renders the label and hides the visually-hidden percent span when label: is given" do
      fragment = component_fragment(:progress, percent: 30, label: "Uploading")

      expect(fragment.css(".d-flex")).not_to be_empty
      expect(fragment.text).to include("Uploading")
      expect(fragment.css(".progress-bar .visually-hidden")).to be_empty
    end

    it "shows the rounded percent alongside the label when show_percent: true" do
      fragment = component_fragment(:progress, percent: 33.333, label: "Uploading", show_percent: true)

      expect(fragment.text).to include("33.3%")
    end

    it "does not render the label row when label: and show_percent: are both omitted" do
      fragment = component_fragment(:progress, percent: 30)

      expect(fragment.css(".d-flex")).to be_empty
    end

    it "renders a visually-hidden percent span in the bar for show_percent: true without a label" do
      fragment = component_fragment(:progress, percent: 45, show_percent: true)

      expect(fragment.css(".d-flex")).to be_empty
      expect(fragment.css(".progress-bar .visually-hidden").first.text).to eq("45.0%")
    end
  end

  describe "accessibility attributes" do
    it "sets role=progressbar and aria-value* reflecting the percentage" do
      fragment = component_fragment(:progress, percent: 63)
      bar = fragment.css(".progress-bar").first

      expect(bar["role"]).to eq("progressbar")
      expect(bar["aria-valuenow"]).to eq("63.0")
      expect(bar["aria-valuemin"]).to eq("0")
      expect(bar["aria-valuemax"]).to eq("100")
    end
  end
end
