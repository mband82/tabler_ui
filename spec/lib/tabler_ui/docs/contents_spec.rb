# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/doc_parser"
require "tabler_ui/docs/demo_registry"
require "tabler_ui/docs/parsed_component"

# The Contents column
# (docs/app/views/tabler_ui/docs/shared/_contents.html.erb, built by
# components/show.html.erb): a right-hand nav treating each demo and each
# documentation section as a chapter of the component page. Reuses two
# existing identifier schemes rather than inventing a third -- demo.slug
# (already the id _demo.html.erb gives its card) for demos, and a
# title-derived "section-<parameterized title>" id (assigned in
# show.html.erb, not by DocParser) for prose sections -- so these specs
# check the Contents column's links resolve against ids that are actually
# on the page, not against a second, independently-computed expectation.
RSpec.describe "TablerUi::Docs Contents column", type: :request do
  # table is the rich case: 6 demos, documented options, and 5 real ##/###
  # sections (Sorting, Filtering, Footer, Turbo Frames, Footer in/filter
  # out) -- see app/components/tabler_ui/table/component.rb's own doc
  # comments. Real content, not a fixture, so this rots if that content is
  # ever stripped down to nothing -- acceptable, table is exactly the page
  # this feature exists for.
  describe "on a component page with demos, options and sections (table)" do
    before { get "/ui/components/table" }

    it "renders 200 with a Contents column" do
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML5.fragment(response.body).at_css("nav.docs-contents")).not_to be_nil
    end

    it "lists one entry per registered demo, linking to that demo's own card id" do
      fragment = Nokogiri::HTML5.fragment(response.body)
      contents = fragment.at_css("nav.docs-contents")
      demos = TablerUi::Docs::DemoRegistry.for(:table)

      expect(demos).not_to be_empty # guards the premise

      demos.each do |demo|
        link = contents.at_css(%(a[href="##{demo.slug}"]))
        expect(link).not_to be_nil, "expected a Contents entry linking to ##{demo.slug}"
        expect(link.text.strip).to eq(demo.toc_label)

        expect(fragment.at_css("##{demo.slug}")).not_to be_nil, "##{demo.slug} isn't actually on the page"
      end
    end

    it "gives a shortened entry's link a title: attribute with the full text, and no title: when unchanged" do
      fragment = Nokogiri::HTML5.fragment(response.body)
      contents = fragment.at_css("nav.docs-contents")
      demos = TablerUi::Docs::DemoRegistry.for(:table)

      shortened_demo = demos.find { |demo| demo.toc_label != demo.title }
      unchanged_demo = demos.find { |demo| demo.toc_label == demo.title }
      expect(shortened_demo).not_to be_nil # guards the premise: table has a long-titled demo
      expect(unchanged_demo).not_to be_nil # guards the premise: table has a short-titled demo too

      shortened_link = contents.at_css(%(a[href="##{shortened_demo.slug}"]))
      expect(shortened_link["title"]).to eq(shortened_demo.title)

      unchanged_link = contents.at_css(%(a[href="##{unchanged_demo.slug}"]))
      expect(unchanged_link["title"]).to be_nil
    end

    it "links 'Options' and 'Examples' to their own headings" do
      fragment = Nokogiri::HTML5.fragment(response.body)
      contents = fragment.at_css("nav.docs-contents")
      parsed = TablerUi::Docs::DocParser.find("table")

      expect(parsed.options).not_to be_empty # guards the premise (29 rows today)
      expect(contents.at_css(%(a[href="#options"])).text.strip).to eq("Options")
      expect(fragment.at_css("#options").name).to eq("h2")

      if parsed.examples.any?
        expect(contents.at_css(%(a[href="#examples"])).text.strip).to eq("Examples")
        expect(fragment.at_css("#examples").name).to eq("h2")
      end
    end

    it "lists one entry per prose section, linking to that section's own heading id" do
      fragment = Nokogiri::HTML5.fragment(response.body)
      contents = fragment.at_css("nav.docs-contents")
      sections = TablerUi::Docs::DocParser.find("table").sections

      expect(sections).not_to be_empty # guards the premise

      sections.each do |section|
        link = contents.css("a").find { |a| a.text.strip == section.title }
        expect(link).not_to be_nil, "expected a Contents entry for section #{section.title.inspect}"

        target = fragment.at_css(link["href"])
        expect(target).not_to be_nil, "#{link["href"]} isn't actually on the page"
        expect(target.name).to eq("h#{section.level}")
        expect(target.text.strip).to eq(section.title)
      end
    end

    it "is hidden below the lg breakpoint via the column wrapping it, not the partial itself" do
      fragment = Nokogiri::HTML5.fragment(response.body)
      column = fragment.at_css("nav.docs-contents").ancestors(".col-lg-2").first

      expect(column).not_to be_nil
      expect(column["class"]).to include("d-none")
      expect(column["class"]).to include("d-lg-block")
    end
  end

  describe "a component page with nothing to list" do
    it "renders no Contents column, and the content column falls back to full width" do
      allow(TablerUi::Docs::DocParser).to receive(:find).and_call_original
      allow(TablerUi::Docs::DocParser).to receive(:find).with("icon").and_return(TablerUi::Docs::ParsedComponent.new("icon"))
      allow(TablerUi::Docs::DemoRegistry).to receive(:for).and_call_original
      allow(TablerUi::Docs::DemoRegistry).to receive(:for).with(:icon).and_return([])

      get "/ui/components/icon"

      expect(response).to have_http_status(:ok)
      fragment = Nokogiri::HTML5.fragment(response.body)
      expect(fragment.at_css("nav.docs-contents")).to be_nil
      expect(fragment.at_css(".col-lg-10.docs-content")).not_to be_nil
    end
  end

  describe "two sections sharing an identical title" do
    it "dedupes their ids with a numeric suffix instead of colliding" do
      duplicate_sections = [
        TablerUi::Docs::ParsedComponent::Section.new("Notes", 2, "First copy."),
        TablerUi::Docs::ParsedComponent::Section.new("Notes", 2, "Second copy.")
      ]
      parsed = TablerUi::Docs::ParsedComponent.new("icon", sections: duplicate_sections)

      allow(TablerUi::Docs::DocParser).to receive(:find).and_call_original
      allow(TablerUi::Docs::DocParser).to receive(:find).with("icon").and_return(parsed)

      get "/ui/components/icon"

      fragment = Nokogiri::HTML5.fragment(response.body)
      expect(fragment.at_css("#section-notes").text.strip).to eq("Notes")
      expect(fragment.at_css("#section-notes-2").text.strip).to eq("Notes")

      hrefs = fragment.at_css("nav.docs-contents").css("a").map { |a| a["href"] }
      expect(hrefs).to include("#section-notes", "#section-notes-2")
    end
  end
end
