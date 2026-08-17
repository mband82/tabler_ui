# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Dimmer", type: :component do
  it "renders with no arguments and no block, without raising" do
    fragment = nil

    expect { fragment = component_fragment(:dimmer) }.not_to raise_error
    expect(fragment.css(".dimmer")).not_to be_empty
    expect(fragment.css(".dimmer-content")).not_to be_empty
    expect(fragment.css(".loader")).not_to be_empty
  end

  it_behaves_like "an element with an html hook", :dimmer, {},
    hook: :html, selector: ".dimmer"

  it_behaves_like "an element with an html hook", :dimmer, {},
    hook: :loader_html, selector: ".loader"

  it_behaves_like "an element with an html hook", :dimmer, {},
    hook: :content_html, selector: ".dimmer-content"

  it "adds .active when active: true" do
    fragment = component_fragment(:dimmer, active: true)

    expect(fragment.css(".dimmer").first["class"].split(/\s+/)).to include("active")
  end

  it "does not add .active when active: is omitted" do
    fragment = component_fragment(:dimmer)

    expect(fragment.css(".dimmer").first["class"].split(/\s+/)).not_to include("active")
  end

  it "does not add .active when active: false" do
    fragment = component_fragment(:dimmer, active: false)

    expect(fragment.css(".dimmer").first["class"].split(/\s+/)).not_to include("active")
  end

  it "renders the block's content inside .dimmer-content" do
    fragment = component_fragment(:dimmer) do |slots|
      slots.content { "Dimmed content" }
    end

    expect(fragment.css(".dimmer-content").text.strip).to eq("Dimmed content")
  end

  it "renders the .loader element regardless of active state" do
    inactive = component_fragment(:dimmer)
    active = component_fragment(:dimmer, active: true)

    expect(inactive.css(".loader")).not_to be_empty
    expect(active.css(".loader")).not_to be_empty
  end

  it "sets aria-busy=true on the root when active" do
    fragment = component_fragment(:dimmer, active: true)

    expect(fragment.css(".dimmer").first["aria-busy"]).to eq("true")
  end

  it "sets aria-busy=false on the root when inactive" do
    fragment = component_fragment(:dimmer)

    expect(fragment.css(".dimmer").first["aria-busy"]).to eq("false")
  end

  it "gives the loader a role=status and visually-hidden accessible text" do
    fragment = component_fragment(:dimmer, active: true)
    loader = fragment.css(".loader").first

    expect(loader["role"]).to eq("status")
    expect(loader.css(".visually-hidden").text).to eq(I18n.t("tabler_ui.dimmer.loader_label"))
  end
end
