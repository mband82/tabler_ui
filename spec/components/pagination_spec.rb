# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Pagination", type: :component do
  # Reduces a rendered fragment to the sequence of page numbers/gaps between
  # prev and next -- e.g. [1, :gap, 8, 9, 10] -- so range-algorithm specs can
  # assert on shape without caring about URLs or exact markup.
  def page_shape(fragment)
    fragment.css("li.page-item").filter_map do |li|
      classes = li["class"].to_s.split(/\s+/)
      next nil if (classes & %w[page-prev page-next]).any?

      classes.include?("disabled") ? :gap : Integer(li.text.strip)
    end
  end

  def prev_li(fragment)
    fragment.css("li.page-item.page-prev").first
  end

  def next_li(fragment)
    fragment.css("li.page-item.page-next").first
  end

  it "renders with no arguments and no block, without raising" do
    fragment = component_fragment(:pagination)

    expect(fragment.css("nav")).not_to be_empty
    expect(fragment.css("ul.pagination")).not_to be_empty
    expect(fragment.css("li.page-item")).to be_empty
  end

  it "yields the component itself, in builder style" do
    expect(TablerUi::Pagination::Component.builder_style?).to be(true)

    yielded = nil
    component_fragment(:pagination) do |pagination|
      yielded = pagination
    end

    expect(yielded).to be_a(TablerUi::Pagination::Component)
    expect(yielded).to respond_to(:item, :gap, :prev, :next)
  end

  describe "builder mode" do
    it "renders items, prev and next in order" do
      fragment = component_fragment(:pagination) do |p|
        p.prev(url: "/1")
        p.item(1, url: "/1")
        p.item(2, url: "/2", active: true)
        p.gap
        p.item(5, url: "/5")
        p.next(url: "/3")
      end

      lis = fragment.css("ul.pagination > li")
      expect(lis.map { |li| li["class"].split(/\s+/).first }).to eq(%w[page-item] * 6)
      expect(prev_li(fragment)).not_to be_nil
      expect(next_li(fragment)).not_to be_nil
      expect(page_shape(fragment)).to eq([1, 2, :gap, 5])
    end

    it "item: with url: renders a link, page number as the text" do
      fragment = component_fragment(:pagination) { |p| p.item(7, url: "/7") }

      link = fragment.css("li.page-item a.page-link").first
      expect(link["href"]).to eq("/7")
      expect(link.text.strip).to eq("7")
    end

    it "item: without url: renders non-linkable text" do
      fragment = component_fragment(:pagination) { |p| p.item(7) }

      li = fragment.css("li.page-item").first
      expect(li.css("a")).to be_empty
      expect(li.css("span.page-link").first.text.strip).to eq("7")
    end

    it "item: disabled: true renders non-linkable text even with a url:" do
      fragment = component_fragment(:pagination) { |p| p.item(7, url: "/7", disabled: true) }

      li = fragment.css("li.page-item").first
      expect(li["class"].split(/\s+/)).to include("disabled")
      expect(li.css("a")).to be_empty
    end

    it "item: active: true marks the item active with aria-current=page" do
      fragment = component_fragment(:pagination) do |p|
        p.item(1, url: "/1")
        p.item(2, url: "/2", active: true)
      end

      lis = fragment.css("li.page-item")
      expect(lis[0]["class"].split(/\s+/)).not_to include("active")
      expect(lis[0]["aria-current"]).to be_nil
      expect(lis[1]["class"].split(/\s+/)).to include("active")
      expect(lis[1]["aria-current"]).to eq("page")
    end

    it "gap renders non-linkable text and carries no page number" do
      fragment = component_fragment(:pagination) { |p| p.gap }

      li = fragment.css("li.page-item").first
      expect(li["class"].split(/\s+/)).to include("disabled")
      expect(li.css("a")).to be_empty
      expect(li.css("span.page-link").first.text.strip).to eq(I18n.t("tabler_ui.pagination.gap", default: "…"))
    end

    it "prev renders page-item page-prev, with a translated default label" do
      fragment = component_fragment(:pagination) { |p| p.prev(url: "/0") }

      li = prev_li(fragment)
      expect(li).not_to be_nil
      expect(li.css("a.page-link").first["href"]).to eq("/0")
      expect(li.text.strip).to eq(I18n.t("tabler_ui.pagination.prev", default: "Previous"))
    end

    it "next renders page-item page-next, with a translated default label" do
      fragment = component_fragment(:pagination) { |p| p.next(url: "/2") }

      li = next_li(fragment)
      expect(li).not_to be_nil
      expect(li.css("a.page-link").first["href"]).to eq("/2")
      expect(li.text.strip).to eq(I18n.t("tabler_ui.pagination.next", default: "Next"))
    end

    it "prev/next label: overrides the translated default" do
      fragment = component_fragment(:pagination) { |p| p.prev(url: "/0", label: "Back") }

      expect(prev_li(fragment).text.strip).to eq("Back")
    end

    it "prev/next without url: render as non-linkable, disabled text" do
      fragment = component_fragment(:pagination) { |p| p.prev(disabled: true) }

      li = prev_li(fragment)
      expect(li["class"].split(/\s+/)).to include("disabled")
      expect(li.css("a")).to be_empty
    end

    it "raises a helpful error when item is called the old keyword way" do
      expect {
        component_fragment(:pagination) { |p| p.item(page: 1) }
      }.to raise_error(ArgumentError, /pagination#item takes page positionally/)
    end
  end

  describe "size:, circle:, outline:" do
    it "size: :sm produces pagination-sm" do
      fragment = component_fragment(:pagination, size: :sm)
      expect(fragment.css("ul.pagination").first["class"].split(/\s+/)).to include("pagination-sm")
    end

    it "size: :lg produces pagination-lg" do
      fragment = component_fragment(:pagination, size: :lg)
      expect(fragment.css("ul.pagination").first["class"].split(/\s+/)).to include("pagination-lg")
    end

    it "no size: produces no size modifier class" do
      fragment = component_fragment(:pagination)
      classes = fragment.css("ul.pagination").first["class"].split(/\s+/)
      expect(classes).not_to include("pagination-sm", "pagination-lg")
    end

    it "raises ArgumentError naming the component on an unknown size" do
      expect { component_fragment(:pagination, size: :xl) }
        .to raise_error(ArgumentError, /unknown pagination size.*xl/)
    end

    it "circle: true produces pagination-circle" do
      fragment = component_fragment(:pagination, circle: true)
      expect(fragment.css("ul.pagination").first["class"].split(/\s+/)).to include("pagination-circle")
    end

    it "outline: true produces pagination-outline" do
      fragment = component_fragment(:pagination, outline: true)
      expect(fragment.css("ul.pagination").first["class"].split(/\s+/)).to include("pagination-outline")
    end
  end

  describe "computed mode -- the range algorithm" do
    def shape_for(current:, total:, window: 2)
      fragment = component_fragment(:pagination, current: current, total: total, window: window,
                                                   url: ->(n) { "/p/#{n}" })
      page_shape(fragment)
    end

    it "total: 0 renders nothing" do
      fragment = component_fragment(:pagination, current: 1, total: 0, url: ->(n) { "/p/#{n}" })
      expect(fragment.css("li.page-item")).to be_empty
    end

    it "total: 1 renders a single active page with prev/next both disabled" do
      fragment = component_fragment(:pagination, current: 1, total: 1, url: ->(n) { "/p/#{n}" })

      expect(page_shape(fragment)).to eq([1])
      expect(fragment.css("li.page-item.active").first["class"].split(/\s+/)).to include("active")
      expect(prev_li(fragment)["class"].split(/\s+/)).to include("disabled")
      expect(next_li(fragment)["class"].split(/\s+/)).to include("disabled")
    end

    it "total: 2 shows both pages with no gap" do
      expect(shape_for(current: 1, total: 2)).to eq([1, 2])
    end

    it "current at the first page has no leading gap" do
      expect(shape_for(current: 1, total: 10)).to eq([1, 2, 3, :gap, 10])
    end

    it "current at the last page has no trailing gap" do
      expect(shape_for(current: 10, total: 10)).to eq([1, :gap, 8, 9, 10])
    end

    it "window wider than total shows every page, no gaps" do
      expect(shape_for(current: 3, total: 5, window: 10)).to eq([1, 2, 3, 4, 5])
    end

    it "a gap on both sides when current is in the middle" do
      expect(shape_for(current: 10, total: 20)).to eq([1, :gap, 8, 9, 10, 11, 12, :gap, 20])
    end

    it "collapses a single hidden page on the left into the page itself, not a gap" do
      expect(shape_for(current: 4, total: 10, window: 1)).to eq([1, 2, 3, 4, 5, :gap, 10])
    end

    it "collapses a single hidden page on the right into the page itself, not a gap" do
      expect(shape_for(current: 7, total: 10, window: 1)).to eq([1, :gap, 6, 7, 8, 9, 10])
    end

    it "current: 1 disables prev, leaves next enabled" do
      fragment = component_fragment(:pagination, current: 1, total: 10, url: ->(n) { "/p/#{n}" })
      expect(prev_li(fragment)["class"].split(/\s+/)).to include("disabled")
      expect(next_li(fragment)["class"].split(/\s+/)).not_to include("disabled")
    end

    it "current: total disables next, leaves prev enabled" do
      fragment = component_fragment(:pagination, current: 10, total: 10, url: ->(n) { "/p/#{n}" })
      expect(next_li(fragment)["class"].split(/\s+/)).to include("disabled")
      expect(prev_li(fragment)["class"].split(/\s+/)).not_to include("disabled")
    end

    it "current out of range (below 1) raises ArgumentError naming the component" do
      expect { component_fragment(:pagination, current: 0, total: 10, url: ->(n) { "/p/#{n}" }) }
        .to raise_error(ArgumentError, /pagination current: 0.*out of range/)
    end

    it "current out of range (above total) raises ArgumentError naming the component" do
      expect { component_fragment(:pagination, current: 11, total: 10, url: ->(n) { "/p/#{n}" }) }
        .to raise_error(ArgumentError, /pagination current: 11.*out of range/)
    end

    it "current: without total: raises ArgumentError" do
      expect { component_fragment(:pagination, current: 1) }
        .to raise_error(ArgumentError, /pagination current:.*without total:/)
    end

    it "current: defaults to 1 when omitted" do
      fragment = component_fragment(:pagination, total: 5, url: ->(n) { "/p/#{n}" })
      expect(fragment.css("li.page-item.active").first.text.strip).to eq("1")
    end

    it "url: is invoked with the right page number for each rendered link" do
      recorded = []
      url = lambda { |n|
        recorded << n
        "/p/#{n}"
      }

      component_fragment(:pagination, current: 5, total: 10, window: 1, url: url)

      # pages shown: 1, :gap(collapsed none here), 4,5,6, :gap, 10 plus prev(4)/next(6)
      expect(recorded).to match_array([1, 4, 4, 5, 6, 6, 10])
    end

    it "url: is not invoked for a disabled prev/next at the boundaries" do
      recorded = []
      url = ->(n) { recorded << n; "/p/#{n}" }

      component_fragment(:pagination, current: 1, total: 3, url: url)

      expect(recorded).not_to include(0)
    end

    it "current:/total: together with a block raises ArgumentError" do
      expect {
        component_fragment(:pagination, current: 1, total: 5, url: ->(n) { "/p/#{n}" }) { |p| p.item(1) }
      }.to raise_error(ArgumentError, /mutually exclusive/)
    end
  end

  it "builder mode and computed mode produce equivalent markup for the same logical input" do
    url = ->(n) { "/p/#{n}" }

    computed = component_fragment(:pagination, current: 5, total: 10, window: 2, url: url)

    builder = component_fragment(:pagination) do |p|
      p.prev(url: url.call(4))
      p.item(1, url: url.call(1))
      p.item(2, url: url.call(2))
      p.item(3, url: url.call(3))
      p.item(4, url: url.call(4))
      p.item(5, url: url.call(5), active: true)
      p.item(6, url: url.call(6))
      p.item(7, url: url.call(7))
      p.gap
      p.item(10, url: url.call(10))
      p.next(url: url.call(6))
    end

    expect(computed.to_html).to eq(builder.to_html)
  end

  it_behaves_like "an element with an html hook", :pagination, {}, hook: :html, selector: "ul.pagination"

  it_behaves_like "an element with an html hook", :pagination,
                   { current: 1, total: 5, url: ->(n) { "/p/#{n}" } },
                   hook: :item_html, selector: "li.page-item.active"

  it "applies per-item html: to that item only, via a plain Hash" do
    fragment = component_fragment(:pagination) do |p|
      p.item(1, url: "/1", html: { class: "hook-extra-class", id: "hook-test-id" })
      p.item(2, url: "/2")
    end

    items = fragment.css("li.page-item")
    expect(items[0]["class"].split(/\s+/)).to include("hook-extra-class")
    expect(items[0]["id"]).to eq("hook-test-id")
    expect(items[1]["class"].split(/\s+/)).not_to include("hook-extra-class")
  end

  it "applies per-item html: to that item only, via a callable taking the item" do
    fragment = component_fragment(:pagination) do |p|
      p.item(1, url: "/1", html: ->(item) { { class: "callable-class-#{item.page}" } })
      p.item(2, url: "/2", html: ->(item) { { class: "callable-class-#{item.page}" } })
    end

    items = fragment.css("li.page-item")
    expect(items[0]["class"].split(/\s+/)).to include("callable-class-1")
    expect(items[1]["class"].split(/\s+/)).to include("callable-class-2")
    expect(items[1]["class"].split(/\s+/)).not_to include("callable-class-1")
  end

  describe "accessibility markup" do
    it "wraps the list in a nav landmark with a translated aria-label" do
      fragment = component_fragment(:pagination)

      nav = fragment.css("nav").first
      expect(nav).not_to be_nil
      expect(nav["aria-label"]).to eq(I18n.t("tabler_ui.pagination.aria_label", default: "Pagination"))
      expect(nav.css("ul.pagination")).not_to be_empty
    end

    it "gives the active page aria-current=\"page\"" do
      fragment = component_fragment(:pagination, current: 2, total: 3, url: ->(n) { "/p/#{n}" })

      active = fragment.css("li.page-item.active").first
      expect(active["aria-current"]).to eq("page")
    end

    it "disabled items render as span, not a focusable link" do
      fragment = component_fragment(:pagination, current: 1, total: 3, url: ->(n) { "/p/#{n}" })

      disabled_prev = prev_li(fragment)
      expect(disabled_prev.css("a")).to be_empty
      expect(disabled_prev.css("span.page-link")).not_to be_empty
    end
  end

  describe "frame:" do
    it "DEGRADATION: with no frame:, renders no turbo-frame element and no turbo attribute anywhere" do
      fragment = component_fragment(:pagination, current: 5, total: 10, url: ->(n) { "/p/#{n}" })

      expect(fragment.css("turbo-frame")).to be_empty
      expect(fragment.to_html).not_to match(/turbo/i)
    end

    it "String shorthand and the equivalent Hash form produce identical markup" do
      string_form = component_fragment(:pagination, current: 5, total: 10, url: ->(n) { "/p/#{n}" }, frame: "tbl")
      hash_form = component_fragment(:pagination, current: 5, total: 10, url: ->(n) { "/p/#{n}" },
                                                   frame: { id: "tbl" })

      expect(string_form.to_html).to eq(hash_form.to_html)
    end

    it "every linkable a.page-link carries data-turbo-frame" do
      fragment = component_fragment(:pagination, current: 5, total: 10, url: ->(n) { "/p/#{n}" }, frame: "tbl")

      links = fragment.css("a.page-link")
      expect(links).not_to be_empty
      links.each { |link| expect(link["data-turbo-frame"]).to eq("tbl") }
    end

    it "gap and disabled prev/next render as span.page-link and do not carry data-turbo-frame" do
      fragment = component_fragment(:pagination, current: 1, total: 10, url: ->(n) { "/p/#{n}" }, frame: "tbl")

      spans = fragment.css("span.page-link")
      expect(spans).not_to be_empty
      spans.each { |span| expect(span.attribute("data-turbo-frame")).to be_nil }
    end

    it "never emits a <turbo-frame> element itself -- it only targets one" do
      fragment = component_fragment(:pagination, current: 5, total: 10, url: ->(n) { "/p/#{n}" }, frame: "tbl")

      expect(fragment.css("turbo-frame")).to be_empty
    end

    it "silently ignores advance:/src:/loading: in a shared frame: hash instead of raising, so a " \
       "table's frame: hash can be passed straight through to pagination" do
      shared_frame = { id: "tbl", advance: false, src: "/x", loading: :lazy }

      expect {
        component_fragment(:pagination, current: 1, total: 3, url: ->(n) { "/p/#{n}" }, frame: shared_frame)
      }.not_to raise_error
    end

    it "raises ArgumentError for a blank frame: { id: }" do
      expect {
        component_fragment(:pagination, current: 1, total: 3, url: ->(n) { "/p/#{n}" }, frame: { id: "" })
      }.to raise_error(ArgumentError, /id/)
    end

    it_behaves_like "an element with an html hook", :pagination,
                     { current: 1, total: 5, url: ->(n) { "/p/#{n}" } },
                     hook: :link_html, selector: "a.page-link"

    it "applies link_html: as a callable per item, so links can differ" do
      fragment = component_fragment(
        :pagination, current: 1, total: 3, url: ->(n) { "/p/#{n}" },
                     link_html: ->(item) { item.page == 1 ? { class: "hook-a" } : { class: "hook-b" } }
      )

      page1 = fragment.css("a.page-link").find { |link| link.text.strip == "1" }
      page2 = fragment.css("a.page-link").find { |link| link.text.strip == "2" }

      expect(page1["class"].split(/\s+/)).to include("hook-a")
      expect(page2["class"].split(/\s+/)).to include("hook-b")
    end
  end
end
