# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Steps", type: :component do
  it "renders with no arguments and no items, without raising" do
    fragment = component_fragment(:steps)

    expect(fragment.css("ul.steps")).not_to be_empty
    expect(fragment.css(".step-item")).to be_empty
  end

  it "yields the component itself, in builder style" do
    expect(TablerUi::Steps::Component.builder_style?).to be(true)

    yielded = nil
    component_fragment(:steps) do |steps|
      yielded = steps
    end

    expect(yielded).to be_a(TablerUi::Steps::Component)
    expect(yielded).to respond_to(:item)
  end

  it "renders items in order" do
    fragment = component_fragment(:steps) do |steps|
      steps.item("Account")
      steps.item("Profile")
      steps.item("Confirm")
    end

    expect(fragment.css(".step-item").map(&:text).map(&:strip)).to eq(%w[Account Profile Confirm])
  end

  it "url: renders a link" do
    fragment = component_fragment(:steps) do |steps|
      steps.item("Account", url: "/account")
    end

    link = fragment.css("a.step-item").first
    expect(link).not_to be_nil
    expect(link["href"]).to eq("/account")
  end

  it "absence of url: does not render a link" do
    fragment = component_fragment(:steps) do |steps|
      steps.item("Account")
    end

    expect(fragment.css("a.step-item")).to be_empty
    expect(fragment.css("li.step-item")).not_to be_empty
  end

  it "raises a helpful error when item is called the old keyword way" do
    expect {
      component_fragment(:steps) { |steps| steps.item(title: "Account") }
    }.to raise_error(ArgumentError, /steps#item takes title positionally/)
  end

  it "current: 2 marks the second item active, and only that one" do
    fragment = component_fragment(:steps, current: 2) do |steps|
      steps.item("Account")
      steps.item("Profile")
      steps.item("Confirm")
    end

    items = fragment.css(".step-item")
    expect(items.map { |i| i["class"].split(/\s+/).include?("active") }).to eq([false, true, false])
  end

  it "defaults current: to 1, marking the first item active" do
    fragment = component_fragment(:steps) do |steps|
      steps.item("Account")
      steps.item("Profile")
    end

    items = fragment.css(".step-item")
    expect(items[0]["class"].split(/\s+/)).to include("active")
    expect(items[1]["class"].split(/\s+/)).not_to include("active")
  end

  it "the active item gets aria-current=\"step\"" do
    fragment = component_fragment(:steps, current: 2) do |steps|
      steps.item("Account")
      steps.item("Profile")
    end

    items = fragment.css(".step-item")
    expect(items[0]["aria-current"]).to be_nil
    expect(items[1]["aria-current"]).to eq("step")
  end

  it "the root list has an accessible label" do
    fragment = component_fragment(:steps)

    expect(fragment.css("ul.steps").first["aria-label"]).to be_present
  end

  # :current can only be range-checked once the builder block has added every
  # item, so Component#validate! runs from TablerUi::Ui after the block is
  # captured and before the partial renders. That keeps this a plain
  # ArgumentError rather than an ActionView::Template::Error wrapping one.
  it "current: beyond the item count raises ArgumentError naming the component" do
    expect {
      component_fragment(:steps, current: 4) do |steps|
        steps.item("Account")
        steps.item("Profile")
        steps.item("Confirm")
      end
    }.to raise_error(ArgumentError, /steps.*current/)
  end

  it "current: below 1 raises ArgumentError" do
    expect {
      component_fragment(:steps, current: 0) do |steps|
        steps.item("Account")
        steps.item("Profile")
      end
    }.to raise_error(ArgumentError, /steps.*current/)
  end

  it "current: out of range with no items does not raise -- there is nothing to validate against" do
    fragment = component_fragment(:steps, current: 5)

    expect(fragment.css("ul.steps")).not_to be_empty
  end

  it "there is no per-item active: -- passing it does not mark a step active" do
    fragment = component_fragment(:steps, current: 1) do |steps|
      steps.item("Account", active: true)
      steps.item("Profile", active: true)
    end

    items = fragment.css(".step-item")
    expect(items[0]["class"].split(/\s+/)).to include("active")
    expect(items[1]["class"].split(/\s+/)).not_to include("active")
  end

  it "vertical: true produces steps-vertical" do
    fragment = component_fragment(:steps, vertical: true)

    expect(fragment.css("ul.steps").first["class"].split(/\s+/)).to include("steps-vertical")
  end

  it "vertical: not given does not produce steps-vertical" do
    fragment = component_fragment(:steps)

    expect(fragment.css("ul.steps").first["class"].split(/\s+/)).not_to include("steps-vertical")
  end

  it "counter: true produces steps-counter" do
    fragment = component_fragment(:steps, counter: true)

    expect(fragment.css("ul.steps").first["class"].split(/\s+/)).to include("steps-counter")
  end

  it "color: produces steps-<color> for a Tabler palette name" do
    fragment = component_fragment(:steps, color: "azure")

    expect(fragment.css("ul.steps").first["class"].split(/\s+/)).to include("steps-azure")
  end

  it "color: with a Bootstrap semantic name raises ArgumentError -- the stylesheet has no such class" do
    expect { component_fragment(:steps, color: "primary") }
      .to raise_error(ArgumentError, /unknown color.*steps/)
  end

  it "raises ArgumentError naming the component on an unknown color" do
    expect { component_fragment(:steps, color: "not-a-color") }
      .to raise_error(ArgumentError, /unknown color.*steps/)
  end

  it "light: combined with color: produces the steps-<color>-lt variant instead of steps-<color>" do
    fragment = component_fragment(:steps, color: "azure", light: true)

    classes = fragment.css("ul.steps").first["class"].split(/\s+/)
    expect(classes).to include("steps-azure-lt")
    expect(classes).not_to include("steps-azure")
  end

  it_behaves_like "an element with an html hook", :steps, {},
    hook: :html, selector: "ul.steps"

  it "applies per-item html: to that item only, via a plain Hash" do
    fragment = component_fragment(:steps) do |steps|
      steps.item("First", html: { class: "hook-extra-class", id: "hook-test-id" })
      steps.item("Second")
    end

    items = fragment.css(".step-item")

    expect(items[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(items[0]["id"]).to eq("hook-test-id")
    expect(items[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
    expect(items[1]["id"]).to be_nil
  end

  it "applies per-item html: to that item only, via a callable taking the item" do
    fragment = component_fragment(:steps) do |steps|
      steps.item("First", html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
      steps.item("Second", html: ->(item) { { class: "callable-class-#{item.title.downcase}" } })
    end

    items = fragment.css(".step-item")

    expect(items[0]["class"].split(/\s+/)).to include("callable-class-first")
    expect(items[0]["class"].split(/\s+/)).not_to include("callable-class-second")
    expect(items[1]["class"].split(/\s+/)).to include("callable-class-second")
    expect(items[1]["class"].split(/\s+/)).not_to include("callable-class-first")
  end
end
