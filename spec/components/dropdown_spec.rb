# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Dropdown", type: :component do
  it "renders with no arguments" do
    fragment = component_fragment(:dropdown)

    expect(fragment.css(".dropdown")).not_to be_empty
    expect(fragment.css(".dropdown-toggle")).not_to be_empty
    expect(fragment.css(".dropdown-menu")).not_to be_empty
  end

  it "yields the component itself, in builder style" do
    expect(TablerUi::Dropdown::Component.builder_style?).to be(true)

    yielded = nil
    component_fragment(:dropdown) do |dropdown|
      yielded = dropdown
    end

    expect(yielded).to be_a(TablerUi::Dropdown::Component)
    expect(yielded).to respond_to(:item)
  end

  it "renders item, divider, and header" do
    fragment = component_fragment(:dropdown, label: "Actions") do |dropdown|
      dropdown.item("Edit", url: "/edit")
      dropdown.divider
      dropdown.header("Danger zone")
    end

    expect(fragment.css(".dropdown-item").map(&:text).map(&:strip)).to include("Edit")
    expect(fragment.css(".dropdown-divider")).not_to be_empty
    expect(fragment.css(".dropdown-header").first.text.strip).to eq("Danger zone")
  end

  it "renders a method: item as a button_to form instead of a link" do
    fragment = component_fragment(:dropdown) do |dropdown|
      dropdown.item("Delete", url: "/widgets/1", method: :delete)
    end

    expect(fragment.css("form .dropdown-item")).not_to be_empty
    expect(fragment.css("a.dropdown-item")).to be_empty
  end

  it "raises a helpful error when item is called the old keyword way" do
    expect {
      component_fragment(:dropdown) { |dropdown| dropdown.item(title: "Edit") }
    }.to raise_error(ArgumentError, /dropdown#item takes title positionally/)
  end

  it "raises a helpful error when header is called the old keyword way" do
    expect {
      component_fragment(:dropdown) { |dropdown| dropdown.header(title: "Danger zone") }
    }.to raise_error(ArgumentError, /dropdown#header takes title positionally/)
  end

  it "align: :end produces dropdown-menu-end" do
    fragment = component_fragment(:dropdown, align: :end)

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).to include("dropdown-menu-end")
  end

  it "align: :start does not produce dropdown-menu-end" do
    fragment = component_fragment(:dropdown, align: :start)

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).not_to include("dropdown-menu-end")
  end

  it "align: nil does not produce dropdown-menu-end" do
    fragment = component_fragment(:dropdown, align: nil)

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).not_to include("dropdown-menu-end")
  end

  it 'align: "end" (string) produces dropdown-menu-end' do
    fragment = component_fragment(:dropdown, align: "end")

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).to include("dropdown-menu-end")
  end

  it 'align: "right" raises ArgumentError -- the old vocabulary is no longer silently coerced' do
    expect { component_fragment(:dropdown, align: "right") }
      .to raise_error(ArgumentError, /:start.*:end/)
  end

  it "align: :middle raises ArgumentError" do
    expect { component_fragment(:dropdown, align: :middle) }
      .to raise_error(ArgumentError, /:start.*:end/)
  end

  it "color: produces btn-<color> on the toggle button" do
    fragment = component_fragment(:dropdown, color: "danger")

    expect(fragment.css(".dropdown-toggle").first["class"].split(/\s+/)).to include("btn-danger")
  end

  it "raises ArgumentError naming the component on an unknown color" do
    expect { component_fragment(:dropdown, color: "not-a-color") }
      .to raise_error(ArgumentError, /unknown color.*dropdown/)
  end

  it "defaults to btn-primary when color: is not given" do
    fragment = component_fragment(:dropdown)

    expect(fragment.css(".dropdown-toggle").first["class"].split(/\s+/)).to include("btn-primary")
  end

  it "no longer accepts button_variant: -- it does not colour the toggle button" do
    fragment = component_fragment(:dropdown, button_variant: "danger")
    classes = fragment.css(".dropdown-toggle").first["class"].split(/\s+/)

    expect(classes).not_to include("btn-danger")
    expect(classes).to include("btn-primary")
  end

  it_behaves_like "an element with an html hook", :dropdown, {},
    hook: :html, selector: ".dropdown"

  it_behaves_like "an element with an html hook", :dropdown, {},
    hook: :toggle_html, selector: ".dropdown-toggle"

  it_behaves_like "an element with an html hook", :dropdown, {},
    hook: :menu_html, selector: ".dropdown-menu"

  it "applies per-item html: to that item only, via a plain Hash" do
    fragment = component_fragment(:dropdown) do |dropdown|
      dropdown.item("First", html: { class: "hook-extra-class", id: "hook-test-id" })
      dropdown.item("Second")
    end

    items = fragment.css(".dropdown-item")

    expect(items[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(items[0]["id"]).to eq("hook-test-id")
    expect(items[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
    expect(items[1]["id"]).to be_nil
  end

  it "applies per-item html: to that item only, via a callable taking the item" do
    fragment = component_fragment(:dropdown) do |dropdown|
      dropdown.item("First", html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
      dropdown.item("Second", html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
    end

    items = fragment.css(".dropdown-item")

    expect(items[0]["class"].split(/\s+/)).to include("callable-class-first")
    expect(items[0]["class"].split(/\s+/)).not_to include("callable-class-second")
    expect(items[1]["class"].split(/\s+/)).to include("callable-class-second")
    expect(items[1]["class"].split(/\s+/)).not_to include("callable-class-first")
  end

  it "renders item icon: as a real icon, not the error-fallback bug icon" do
    fragment = component_fragment(:dropdown) do |dropdown|
      dropdown.item("Edit", icon: "edit")
    end

    svg = fragment.css(".dropdown-item svg").first
    expect(svg).not_to be_nil
    expect(svg["class"].to_s.split(/\s+/)).not_to include("icon-tabler-bug")
  end
end
