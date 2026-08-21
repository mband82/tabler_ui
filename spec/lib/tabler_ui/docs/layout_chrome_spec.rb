# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"

# Structural checks for the docs engine's chrome
# (docs/app/views/layouts/tabler_ui/docs/application.html.erb): the navbar
# (brand + search + dark mode toggle), the sticky breadcrumb bar (component
# pages only), and the widened content column. Visual/interactive
# properties (does it actually stay pinned while scrolling, does the toggle
# actually flip the theme) are out of scope for a request spec -- these
# only assert the markup/classes that drive that behaviour are present.
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
  end

  describe "the sticky breadcrumb bar" do
    it "is present on a component page, sticky, with Overview/category/component items" do
      get "/ui/components/badge"

      fragment = Nokogiri::HTML5.fragment(response.body)
      bar = fragment.at_css(".docs-breadcrumb-bar")

      expect(bar).not_to be_nil
      expect(bar["class"]).to include("sticky-top")

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
      expect(fragment.at_css(".col-lg-10")).not_to be_nil
    end
  end
end
