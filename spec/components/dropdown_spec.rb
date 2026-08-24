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

  it "renders item icon: with dropdown-item-icon, not the old me-1 utility class" do
    fragment = component_fragment(:dropdown) do |dropdown|
      dropdown.item("Edit", icon: "edit")
    end

    svg = fragment.css(".dropdown-item svg").first
    classes = svg["class"].to_s.split(/\s+/)

    expect(classes).to include("dropdown-item-icon")
    expect(classes).not_to include("me-1")
  end

  it "dark: true adds dropdown-menu-dark to the menu" do
    fragment = component_fragment(:dropdown, dark: true)

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).to include("dropdown-menu-dark")
  end

  it "without dark:, the menu has no dropdown-menu-dark" do
    fragment = component_fragment(:dropdown)

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).not_to include("dropdown-menu-dark")
  end

  it "scrollable: true adds dropdown-menu-scrollable to the menu" do
    fragment = component_fragment(:dropdown, scrollable: true)

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).to include("dropdown-menu-scrollable")
  end

  it "arrow: true adds dropdown-menu-arrow to the menu" do
    fragment = component_fragment(:dropdown, arrow: true)

    expect(fragment.css(".dropdown-menu").first["class"].split(/\s+/)).to include("dropdown-menu-arrow")
  end

  it "arrow: true combined with align: :end emits both classes, side by side" do
    fragment = component_fragment(:dropdown, arrow: true, align: :end)
    classes = fragment.css(".dropdown-menu").first["class"].split(/\s+/)

    expect(classes).to include("dropdown-menu-arrow")
    expect(classes).to include("dropdown-menu-end")
  end

  it "direction: defaults to down, keeping the plain dropdown wrapper class" do
    fragment = component_fragment(:dropdown)

    expect(fragment.css(".dropdown").first["class"].split(/\s+/)).to include("dropdown")
  end

  {
    "up" => "dropup",
    "end" => "dropend",
    "start" => "dropstart",
    "up-center" => "dropup-center",
    "down-center" => "dropdown-center"
  }.each do |direction, wrapper_class|
    it "direction: #{direction.inspect} emits #{wrapper_class} on the wrapper, replacing dropdown" do
      fragment = component_fragment(:dropdown, direction: direction)
      classes = fragment.css("div").first["class"].split(/\s+/)

      expect(classes).to include(wrapper_class)
      expect(classes).not_to include("dropdown")
    end
  end

  it "raises ArgumentError naming the component on an unknown direction" do
    expect { component_fragment(:dropdown, direction: "sideways") }
      .to raise_error(ArgumentError, /unknown direction.*dropdown/)
  end

  it "align_breakpoint: 'lg' with align: :end emits both dropdown-menu-end and dropdown-menu-lg-end" do
    fragment = component_fragment(:dropdown, align_breakpoint: "lg", align: :end)
    classes = fragment.css(".dropdown-menu").first["class"].split(/\s+/)

    expect(classes).to include("dropdown-menu-end")
    expect(classes).to include("dropdown-menu-lg-end")
  end

  it "raises ArgumentError on an unknown align_breakpoint" do
    expect { component_fragment(:dropdown, align_breakpoint: "not-a-breakpoint") }
      .to raise_error(ArgumentError, /unknown breakpoint/)
  end

  it "default output is unchanged when none of the new options are passed" do
    fragment = component_fragment(:dropdown, label: "Actions") do |dropdown|
      dropdown.item("Edit", url: "/edit")
    end

    wrapper_classes = fragment.css(".dropdown").first["class"].split(/\s+/)
    menu_classes = fragment.css(".dropdown-menu").first["class"].split(/\s+/)

    expect(wrapper_classes).to eq(["dropdown"])
    expect(menu_classes).to eq(["dropdown-menu"])
  end

  # CLAUDE.md rule 8: auth: gating on the dropdown's own subitems (item,
  # divider, header). TablerUi.auth_method is global, process-wide mutable
  # state -- restore it after every example so a custom auth_method here
  # never leaks into specs that run afterward (see authorization_spec.rb /
  # ui_spec.rb's identical around block for the same reasoning).
  describe "auth: gating on subitems" do
    around do |example|
      original = TablerUi.auth_method
      example.run
      TablerUi.auth_method = original
    end

    it "renders exactly as before when default auth_method and no auth: is used anywhere" do
      fragment = component_fragment(:dropdown, label: "Actions") do |dropdown|
        dropdown.item("Edit", url: "/edit")
        dropdown.divider
        dropdown.header("Danger zone")
        dropdown.item("Delete", url: "/delete")
      end

      expect(fragment.css(".dropdown-item").map(&:text).map(&:strip)).to eq(["Edit", "Delete"])
      expect(fragment.css(".dropdown-divider")).not_to be_empty
      expect(fragment.css(".dropdown-header").first.text.strip).to eq("Danger zone")
    end

    it "omits an item whose own auth: is denied" do
      TablerUi.auth_method = ->(value) { value != :denied }

      fragment = component_fragment(:dropdown) do |dropdown|
        dropdown.item("Allowed", auth: :allowed)
        dropdown.item("Denied", auth: :denied)
      end

      titles = fragment.css(".dropdown-item").map(&:text).map(&:strip)
      expect(titles).to include("Allowed")
      expect(titles).not_to include("Denied")
    end

    it "includes an item whose own auth: is authorized" do
      TablerUi.auth_method = ->(value) { value != :denied }

      fragment = component_fragment(:dropdown) do |dropdown|
        dropdown.item("Allowed", auth: :allowed)
      end

      expect(fragment.css(".dropdown-item").map(&:text).map(&:strip)).to include("Allowed")
    end

    it "omits a divider whose own auth: is denied" do
      TablerUi.auth_method = ->(value) { value != :denied }

      fragment = component_fragment(:dropdown) do |dropdown|
        dropdown.item("Kept", auth: :allowed)
        dropdown.divider(auth: :denied)
      end

      expect(fragment.css(".dropdown-divider")).to be_empty
    end

    it "includes a divider whose own auth: is authorized" do
      TablerUi.auth_method = ->(value) { value != :denied }

      fragment = component_fragment(:dropdown) do |dropdown|
        dropdown.divider(auth: :allowed)
      end

      expect(fragment.css(".dropdown-divider")).not_to be_empty
    end

    it "omits a header whose own auth: is denied" do
      TablerUi.auth_method = ->(value) { value != :denied }

      fragment = component_fragment(:dropdown) do |dropdown|
        dropdown.header("Danger zone", auth: :denied)
      end

      expect(fragment.css(".dropdown-header")).to be_empty
    end

    it "includes a header whose own auth: is authorized" do
      TablerUi.auth_method = ->(value) { value != :denied }

      fragment = component_fragment(:dropdown) do |dropdown|
        dropdown.header("Danger zone", auth: :allowed)
      end

      expect(fragment.css(".dropdown-header").first.text.strip).to eq("Danger zone")
    end

    # These four examples build the component directly rather than going
    # through the dispatcher (component_fragment/tabler_ui.dropdown): the
    # dispatcher's own top-level auth: gate (see ui_spec.rb's "auth: gating"
    # describe block) would deny the *entire* dropdown call -- block never
    # run -- whenever the dropdown-level auth: is itself denied, which would
    # make it impossible to exercise #item's inheritance/override branch in
    # that case. Setting .auth= directly is exactly what the dispatcher does
    # internally right after construction (see ui.rb's build path), so this
    # exercises the same inheritance logic without that confound.
    it "an item with no auth: of its own inherits the dropdown's auth: -- denied" do
      TablerUi.auth_method = ->(value) { value != :denied }
      dropdown = TablerUi::Dropdown::Component.new
      dropdown.auth = :denied

      dropdown.item("Inherited")

      expect(dropdown.items).to be_empty
    end

    it "an item with no auth: of its own inherits the dropdown's auth: -- allowed" do
      TablerUi.auth_method = ->(value) { value != :denied }
      dropdown = TablerUi::Dropdown::Component.new
      dropdown.auth = :allowed

      dropdown.item("Inherited")

      expect(dropdown.items.map(&:title)).to include("Inherited")
    end

    it "an item's own auth: overrides an otherwise-denying dropdown auth:" do
      TablerUi.auth_method = ->(value) { value == :allowed }
      dropdown = TablerUi::Dropdown::Component.new
      dropdown.auth = :denied

      dropdown.item("Overridden", auth: :allowed)

      expect(dropdown.items.map(&:title)).to include("Overridden")
    end

    it "an item's own auth: overrides an otherwise-allowing dropdown auth:" do
      TablerUi.auth_method = ->(value) { value != :denied }
      dropdown = TablerUi::Dropdown::Component.new
      dropdown.auth = :allowed

      dropdown.item("Overridden", auth: :denied)

      expect(dropdown.items).to be_empty
    end
  end
end
