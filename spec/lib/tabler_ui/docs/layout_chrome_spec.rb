# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"

# Structural checks for the docs engine's chrome
# (docs/app/views/layouts/tabler_ui/docs/application.html.erb): the fixed
# header (navbar + brand + search + dark mode toggle, plus the breadcrumb
# bar on component pages only), and the widened content column. Visual/
# interactive properties (does it actually stay pinned while scrolling, does
# the offset actually clear the fixed header, does the toggle actually flip
# the theme) are out of scope for a request spec -- these only assert the
# markup/classes/custom-property values that drive that behaviour are
# present.
RSpec.describe "TablerUi::Docs layout chrome", type: :request do
  describe "the navbar" do
    it "renders on every kind of docs page, with a brand link to the index" do
      ["/ui", "/ui/forms", "/ui/components/badge"].each do |path|
        get path

        fragment = Nokogiri::HTML5.fragment(response.body)
        navbar = fragment.at_css("header.navbar")

        expect(navbar).not_to be_nil, "expected a navbar on #{path}"
        # root_path, called from inside this isolated engine's own views,
        # generates the mounted-root path with its conventional trailing
        # slash ("/ui/") -- same as any Rails root_path.
        expect(navbar.at_css(".navbar-brand a[href='/ui/']")).not_to be_nil
      end
    end

    it "contains exactly one search box, not duplicated in the sidebar" do
      get "/ui/components/badge"

      fragment = Nokogiri::HTML5.fragment(response.body)

      expect(fragment.css(".docs-search").size).to eq(1)
      expect(fragment.at_css("header.navbar .docs-search")).not_to be_nil
      expect(fragment.at_css("nav.docs-sidebar .docs-search")).to be_nil
    end

    it "renders the gem's own dark_mode_toggle component, not hand-rolled markup" do
      get "/ui/components/badge"

      fragment = Nokogiri::HTML5.fragment(response.body)
      navbar = fragment.at_css("header.navbar")

      # app/components/tabler_ui/dark_mode_toggle/component.rb's own root
      # element carries this data-controller -- proves the real component
      # rendered, not a copy of its markup.
      expect(navbar.at_css("[data-controller='tabler-ui--dark-mode']")).not_to be_nil
    end

    # Documentation and Editor are the two halves of this engine (see
    # application.html.erb's own comment above the navbar block), so the
    # navbar carries a link to each, on every kind of docs page -- not just
    # the editor page itself (see editor_page_spec.rb for that page marking
    # "Editor" current instead).
    it "links both Documentation and Editor, to the index and the editor page respectively" do
      ["/ui", "/ui/forms", "/ui/components/badge"].each do |path|
        get path

        navbar = Nokogiri::HTML5.fragment(response.body).at_css("header.navbar")
        links = navbar.css("a.nav-link")

        documentation_link = links.find { |a| a.text.strip == "Documentation" }
        editor_link = links.find { |a| a.text.strip == "Editor" }

        expect(documentation_link["href"]).to eq("/ui/"), "expected Documentation to link to the index on #{path}"
        expect(editor_link["href"]).to eq("/ui/editor"), "expected Editor to link to /ui/editor on #{path}"
      end
    end

    it "marks Documentation current, and Editor not current, on an ordinary docs page" do
      get "/ui/components/badge"

      navbar = Nokogiri::HTML5.fragment(response.body).at_css("header.navbar")
      links = navbar.css("a.nav-link")

      documentation_link = links.find { |a| a.text.strip == "Documentation" }
      editor_link = links.find { |a| a.text.strip == "Editor" }

      expect(documentation_link["class"]).to include("active")
      expect(editor_link["class"]).not_to include("active")
    end
  end

  # The navbar and the breadcrumb bar used to be two independent elements --
  # only the breadcrumb bar was sticky, so it lost its own stickiness as
  # soon as the (not sticky at all) navbar above it scrolled out of view.
  # Both are now wrapped in one fixed-position header instead, so the whole
  # thing (navbar included) stays pinned together.
  describe "the fixed header" do
    it "wraps the navbar in a fixed-position header, on every kind of docs page" do
      ["/ui", "/ui/forms", "/ui/components/badge"].each do |path|
        get path

        fragment = Nokogiri::HTML5.fragment(response.body)
        header = fragment.at_css("header.docs-fixed-header")

        expect(header).not_to be_nil, "expected header.docs-fixed-header on #{path}"
        expect(header["class"]).to include("fixed-top")
        expect(header.at_css("header.navbar")).not_to be_nil
      end
    end

    it "also wraps the breadcrumb bar, on a component page" do
      get "/ui/components/badge"

      fragment = Nokogiri::HTML5.fragment(response.body)
      header = fragment.at_css("header.docs-fixed-header")
      bar = header.at_css(".docs-breadcrumb-bar")

      expect(bar).not_to be_nil
      items = bar.css(".breadcrumb-item").map { |item| item.text.strip }
      expect(items).to eq(%w[Overview Content Badge])
    end

    it "sets --docs-header-height once, on the shell wrapping the whole header + page-wrapper" do
      get "/ui/components/badge"

      fragment = Nokogiri::HTML5.fragment(response.body)
      shell = fragment.at_css(".docs-shell")

      expect(shell).not_to be_nil
      expect(shell.at_css("header.docs-fixed-header")).not_to be_nil
      expect(shell.at_css(".page-wrapper")).not_to be_nil
      expect(shell["style"]).to match(/--docs-header-height:\s*[^;]+/)
    end

    it "uses a taller --docs-header-height on a page with a breadcrumb bar than one without" do
      get "/ui/components/badge"
      with_breadcrumb_height = Nokogiri::HTML5.fragment(response.body).at_css(".docs-shell")["style"][/--docs-header-height:\s*([^;]+)/, 1]

      get "/ui"
      without_breadcrumb_height = Nokogiri::HTML5.fragment(response.body).at_css(".docs-shell")["style"][/--docs-header-height:\s*([^;]+)/, 1]

      expect(with_breadcrumb_height).not_to eq(without_breadcrumb_height)
    end
  end

  describe "the breadcrumb bar" do
    it "is present on a component page, with Overview/category/component items" do
      get "/ui/components/badge"

      fragment = Nokogiri::HTML5.fragment(response.body)
      bar = fragment.at_css(".docs-breadcrumb-bar")

      expect(bar).not_to be_nil

      items = bar.css(".breadcrumb-item").map { |item| item.text.strip }
      expect(items).to eq(%w[Overview Content Badge])
    end

    it "is absent on the index (no breadcrumb to promote there)" do
      get "/ui"

      fragment = Nokogiri::HTML5.fragment(response.body)
      expect(fragment.at_css(".docs-breadcrumb-bar")).to be_nil
    end

    it "is absent on the forms harness (no breadcrumb to promote there)" do
      get "/ui/forms"

      fragment = Nokogiri::HTML5.fragment(response.body)
      expect(fragment.at_css(".docs-breadcrumb-bar")).to be_nil
    end
  end

  describe "the content column" do
    it "is wider than the sidebar column, via Bootstrap's grid classes" do
      get "/ui/components/badge"

      fragment = Nokogiri::HTML5.fragment(response.body)

      expect(fragment.at_css(".col-lg-2 nav.docs-sidebar")).not_to be_nil
      # badge has demos and documented options, so the Contents column
      # renders too (see contents_spec.rb) and the content column narrows
      # to make room for it, rather than staying the full col-lg-10 it is
      # when there's no Contents column to share the row with.
      expect(fragment.at_css(".col-lg-8.docs-content")).not_to be_nil
    end

    it "falls back to the full-width column when there's no Contents to make room for" do
      get "/ui"

      fragment = Nokogiri::HTML5.fragment(response.body)
      expect(fragment.at_css(".col-lg-10.docs-content")).not_to be_nil
      expect(fragment.at_css(".col-lg-8.docs-content")).to be_nil
    end
  end
end
