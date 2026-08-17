# frozen_string_literal: true

require "rails_helper"

# Safety net for the TablerUi::Ui dispatcher refactor (lib/tabler_ui/ui.rb):
# every one of the 20 existing components must still render without raising,
# through the real dispatcher, with a minimal-but-valid set of arguments.
#
# This is deliberately not a detailed per-component contract test (that
# comes later, per component) -- it only proves the plumbing still works, so
# that later refactor batches have a baseline to break loudly against.
RSpec.describe "TablerUi component regression render", type: :component do
  # class-backed components (app/components/tabler_ui/<name>/component.rb)
  it "renders alert" do
    fragment = component_fragment(:alert, color: "success", text: "Saved!")

    # Assert the options actually took effect. The previous version passed the
    # since-renamed variant:/message: and still went green, because checking
    # only that ".alert" exists cannot tell a working option from a dead one.
    expect(fragment.css(".alert-success")).not_to be_empty
    expect(fragment.text).to include("Saved!")
  end

  it "renders badge" do
    fragment = component_fragment(:badge, text: "New", color: "blue")

    expect(fragment.css(".badge")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders dark_mode_toggle" do
    fragment = component_fragment(:dark_mode_toggle)

    expect(fragment.css("a")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders datagrid" do
    fragment = component_fragment(:datagrid) { |dg| dg.item("Title", content: "Value") }

    expect(fragment.css(".datagrid-item")).not_to be_empty
    expect(fragment.text).to include("Title", "Value")
  end

  it "renders dropdown" do
    fragment = component_fragment(:dropdown, label: "Actions") { |dd| dd.item("Edit", url: "/edit") }

    expect(fragment.css(".dropdown")).not_to be_empty
    expect(fragment.text).to include("Actions", "Edit")
    expect(fragment.css("a[href='/edit']")).not_to be_empty
  end

  it "renders icon" do
    fragment = component_fragment(:icon, icon: "user")

    expect(fragment.css("svg")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders illustration" do
    fragment = component_fragment(:illustration, name: "boy")

    expect(fragment.css("svg")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders navbar" do
    fragment = component_fragment(:navbar) { |navbar| navbar.brand = "MyApp" }

    expect(fragment.css("header.navbar")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders placeholder" do
    fragment = component_fragment(:placeholder, type: :text, width: 9)

    expect(fragment.css(".placeholder")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders rating" do
    fragment = component_fragment(:rating)

    expect(fragment.css("select")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders settings_page" do
    fragment = component_fragment(:settings_page, id: "settings-1") do |sp|
      sp.item("General") { "General settings content" }
    end

    expect(fragment.css(".tab-pane")).not_to be_empty
    expect(fragment.text).to include("General", "General settings content")
  end

  it "renders status" do
    fragment = component_fragment(:status, text: "Active", color: "green")

    expect(fragment.text).to include("Active")
    expect(fragment.to_html).not_to be_empty
  end

  it "renders tabs" do
    fragment = component_fragment(:tabs, id: "tabs-1") do |tabs|
      tabs.tab("First") { "First tab content" }
    end

    expect(fragment.css(".tab-pane")).not_to be_empty
    expect(fragment.text).to include("First", "First tab content")
  end

  # bare partials (app/components/tabler_ui/_<name>.html.erb) -- OpenStruct
  # fallback, so `component_fragment` builds each straight from kwargs.
  it "renders avatar" do
    fragment = component_fragment(:avatar, name: "Ada Lovelace", size: "md")

    expect(fragment.css("svg, span.avatar")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders button" do
    fragment = component_fragment(:button, text: "Click me", url: "/path")

    expect(fragment.css(".btn")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders card" do
    fragment = component_fragment(:card, title: "Card title") { |slots| slots.body { "Body content" } }

    expect(fragment.css(".card")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
    # Was `class="card OpenStruct"` before card became a real component:
    # `card.respond_to?(:class)` is always true, so the old bare partial
    # leaked Object#class into the class list. See card_spec.rb for the
    # full regression.
    expect(fragment.to_html).not_to include("OpenStruct")
  end

  it "renders page_header" do
    fragment = component_fragment(:page_header, title: "Page title") { |slots| slots.buttons { "" } }

    expect(fragment.css(".page-header")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders progress" do
    fragment = component_fragment(:progress, percent: 42)

    expect(fragment.css(".progress")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders stat_card" do
    fragment = component_fragment(:stat_card, label: "Sales", value: "1,234")

    expect(fragment.css(".card")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end

  it "renders table" do
    columns = [{ label: "Name", class: "", value: ->(row) { row[:name] } }]
    fragment = component_fragment(:table, columns: columns, data: [{ name: "Ada" }])

    expect(fragment.css("table")).not_to be_empty
    expect(fragment.to_html).not_to be_empty
  end
end
