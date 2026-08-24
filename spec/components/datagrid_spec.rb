# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Datagrid", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:datagrid)

    expect(fragment.css(".datagrid")).to be_empty
    expect(fragment.to_html.strip).to eq("")
  end

  it "yields the component itself in builder style" do
    yielded = nil

    component_fragment(:datagrid) do |dg|
      yielded = dg
    end

    expect(TablerUi::Datagrid::Component.builder_style?).to be true
    expect(yielded).to respond_to(:item)
  end

  it "renders items added via the builder, with title and content" do
    fragment = component_fragment(:datagrid) do |dg|
      dg.item "Name", content: "Ada Lovelace"
    end

    expect(fragment.css(".datagrid-title").first.text).to eq("Name")
    expect(fragment.css(".datagrid-content").first.text.strip).to eq("Ada Lovelace")
  end

  it "renders content supplied via options[:content]" do
    fragment = component_fragment(:datagrid) do |dg|
      dg.item "Name", content: "Ada"
    end

    expect(fragment.css(".datagrid-content").first.text.strip).to eq("Ada")
  end

  it "renders content supplied via a block" do
    fragment = component_fragment(:datagrid) do |dg|
      dg.item "Bio" do
        "Mathematician"
      end
    end

    expect(fragment.css(".datagrid-content").first.text.strip).to eq("Mathematician")
  end

  it "prefers the block over options[:content] when both are given" do
    fragment = component_fragment(:datagrid) do |dg|
      dg.item "Name", content: "from option" do
        "from block"
      end
    end

    text = fragment.css(".datagrid-content").first.text.strip
    expect(text).to eq("from block")
    expect(text).not_to include("from option")
  end

  it_behaves_like "an element with an html hook", :datagrid, { items: [{ title: "Name", content: "Ada" }] },
    hook: :html, selector: ".datagrid"

  it "applies item_html: as a plain Hash to every item" do
    fragment = component_fragment(
      :datagrid,
      items: [{ title: "Name", content: "Ada" }, { title: "Bio", content: "Mathematician" }],
      item_html: { class: "all-items" }
    )
    items = fragment.css(".datagrid-item")

    expect(items.size).to eq(2)
    items.each { |item| expect(item["class"].to_s.split(/\s+/)).to include("all-items") }
  end

  it "applies item_html: as a callable, so items can differ" do
    fragment = component_fragment(
      :datagrid,
      items: [{ title: "Name", content: "Ada" }, { title: "Bio", content: "Mathematician" }],
      item_html: ->(item) { item[:title] == "Name" ? { class: "highlight" } : {} }
    )
    items = fragment.css(".datagrid-item")

    expect(items[0]["class"].to_s.split(/\s+/)).to include("highlight")
    expect(items[1]["class"].to_s).not_to include("highlight")
  end

  it "applies title_html: per item" do
    fragment = component_fragment(
      :datagrid,
      items: [{ title: "Name", content: "Ada" }, { title: "Bio", content: "Mathematician" }],
      title_html: ->(item) { item[:title] == "Name" ? { class: "highlight-title" } : {} }
    )
    titles = fragment.css(".datagrid-title")

    expect(titles[0]["class"].to_s.split(/\s+/)).to include("highlight-title")
    expect(titles[1]["class"].to_s).not_to include("highlight-title")
  end

  it "applies content_html: per item" do
    fragment = component_fragment(
      :datagrid,
      items: [{ title: "Name", content: "Ada" }, { title: "Bio", content: "Mathematician" }],
      content_html: ->(item) { item[:title] == "Name" ? { class: "highlight-content" } : {} }
    )
    contents = fragment.css(".datagrid-content")

    expect(contents[0]["class"].to_s.split(/\s+/)).to include("highlight-content")
    expect(contents[1]["class"].to_s).not_to include("highlight-content")
  end

  it "renders items: passed directly at construction alongside the builder" do
    fragment = component_fragment(:datagrid, items: [{ title: "Preset", content: "value" }]) do |dg|
      dg.item "Added", content: "later"
    end

    titles = fragment.css(".datagrid-title").map(&:text)
    expect(titles).to eq(%w[Preset Added])
  end

  # auth: (CLAUDE.md rule 8) -- TablerUi.auth_method is global, process-wide
  # mutable state, so every example that swaps it in must restore the
  # original afterward. Same idiom as spec/lib/tabler_ui/authorization_spec.rb
  # and spec/components/steps_spec.rb.
  describe "auth:" do
    around do |example|
      original = TablerUi.auth_method
      example.run
      TablerUi.auth_method = original
    end

    describe "#item" do
      it "an item with its own auth: denied is not present in the rendered output" do
        TablerUi.auth_method = ->(value) { value != :denied }

        fragment = component_fragment(:datagrid) do |dg|
          dg.item "Account", content: "x", auth: :denied
          dg.item "Profile", content: "y"
        end

        expect(fragment.css(".datagrid-title").map(&:text)).to eq(["Profile"])
      end

      it "an item with its own auth: authorized is present in the rendered output" do
        TablerUi.auth_method = ->(value) { value != :denied }

        fragment = component_fragment(:datagrid) do |dg|
          dg.item "Account", content: "x", auth: :allowed
          dg.item "Profile", content: "y"
        end

        expect(fragment.css(".datagrid-title").map(&:text)).to eq(%w[Account Profile])
      end

      # These examples build the component directly rather than going through
      # the dispatcher (component_fragment/tabler_ui.datagrid): the
      # dispatcher's own top-level auth: gate would deny the *entire*
      # datagrid call whenever datagrid's own auth: is itself denied, which
      # would make it impossible to exercise #item's inheritance/override
      # branch in that case. Setting .auth= directly is exactly what the
      # dispatcher does internally right after construction (see ui.rb's
      # build_modern_component call site), so this exercises the same
      # inheritance logic without that confound.
      it "an item with no auth: of its own inherits datagrid's own auth: -- denied" do
        TablerUi.auth_method = ->(value) { value != :denied }
        datagrid = TablerUi::Datagrid::Component.new
        datagrid.auth = :denied

        datagrid.item "Account", content: "x"

        expect(datagrid.items).to be_empty
      end

      it "an item with no auth: of its own inherits datagrid's own auth: -- allowed" do
        TablerUi.auth_method = ->(value) { value != :denied }
        datagrid = TablerUi::Datagrid::Component.new
        datagrid.auth = :allowed

        datagrid.item "Account", content: "x"

        expect(datagrid.items.map { |i| i[:title] }).to include("Account")
      end

      it "an item's own explicit auth: overrides an unauthorized datagrid-level auth: (allows it through)" do
        TablerUi.auth_method = ->(value) { value == :allowed }
        datagrid = TablerUi::Datagrid::Component.new
        datagrid.auth = :denied

        datagrid.item "Account", content: "x", auth: :allowed

        expect(datagrid.items.map { |i| i[:title] }).to include("Account")
      end

      it "an item's own explicit auth: overrides an authorized datagrid-level auth: (denies it)" do
        TablerUi.auth_method = ->(value) { value != :denied }
        datagrid = TablerUi::Datagrid::Component.new
        datagrid.auth = :allowed

        datagrid.item "Account", content: "x", auth: :denied

        expect(datagrid.items).to be_empty
      end
    end

    describe "construction-time items:" do
      it "an item with its own auth: denied is not present in the rendered output" do
        TablerUi.auth_method = ->(value) { value != :denied }

        fragment = component_fragment(
          :datagrid,
          items: [{ title: "Account", content: "x", auth: :denied }, { title: "Profile", content: "y" }]
        )

        expect(fragment.css(".datagrid-title").map(&:text)).to eq(["Profile"])
      end

      it "an item with its own auth: authorized is present in the rendered output" do
        TablerUi.auth_method = ->(value) { value != :denied }

        fragment = component_fragment(
          :datagrid,
          items: [{ title: "Account", content: "x", auth: :allowed }, { title: "Profile", content: "y" }]
        )

        expect(fragment.css(".datagrid-title").map(&:text)).to eq(%w[Account Profile])
      end

      # Same direct-construction rationale as the #item examples above: the
      # dispatcher's top-level gate would swallow the whole call if
      # datagrid's own auth: were denied, so .auth= is set directly instead
      # to exercise inheritance/override in isolation.
      it "an item with no auth: of its own inherits datagrid's own auth: -- denied" do
        TablerUi.auth_method = ->(value) { value != :denied }
        datagrid = TablerUi::Datagrid::Component.new(items: [{ title: "Account", content: "x" }])
        datagrid.auth = :denied

        expect(datagrid.items).to be_empty
      end

      it "an item with no auth: of its own inherits datagrid's own auth: -- allowed" do
        TablerUi.auth_method = ->(value) { value != :denied }
        datagrid = TablerUi::Datagrid::Component.new(items: [{ title: "Account", content: "x" }])
        datagrid.auth = :allowed

        expect(datagrid.items.map { |i| i[:title] }).to include("Account")
      end

      it "an item's own explicit auth: overrides an unauthorized datagrid-level auth: (allows it through)" do
        TablerUi.auth_method = ->(value) { value == :allowed }
        datagrid = TablerUi::Datagrid::Component.new(items: [{ title: "Account", content: "x", auth: :allowed }])
        datagrid.auth = :denied

        expect(datagrid.items.map { |i| i[:title] }).to include("Account")
      end

      it "an item's own explicit auth: overrides an authorized datagrid-level auth: (denies it)" do
        TablerUi.auth_method = ->(value) { value != :denied }
        datagrid = TablerUi::Datagrid::Component.new(items: [{ title: "Account", content: "x", auth: :denied }])
        datagrid.auth = :allowed

        expect(datagrid.items).to be_empty
      end
    end

    it "renders exactly as before under the default auth_method with no auth: anywhere, on both paths" do
      fragment = component_fragment(:datagrid, items: [{ title: "Preset", content: "value" }]) do |dg|
        dg.item "Added", content: "later"
      end

      titles = fragment.css(".datagrid-title").map(&:text)
      expect(titles).to eq(%w[Preset Added])
    end
  end
end
