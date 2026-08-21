# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/search_index"
require "tabler_ui/docs/navigation"
require "tabler_ui/docs/doc_parser"
require "tabler_ui/docs/demo_registry"

# TablerUi::Docs::SearchIndex builds the docs engine's full-text search
# index from the same three sources every docs page already reads from --
# Navigation, DocParser, DemoRegistry -- so this spec cross-checks the
# built index against those sources directly rather than hardcoding counts
# that would go stale the moment a component's doc comments change.
RSpec.describe TablerUi::Docs::SearchIndex do
  after { described_class.reset! }

  describe ".build" do
    subject(:entries) { described_class.build }

    it "has an entry for every component Navigation knows about" do
      component_entries = entries.select { |e| e[:kind] == "component" }

      expect(component_entries.map { |e| e[:component] }.sort).to eq(TablerUi::Docs::Navigation.components.sort)
    end

    it "has an entry for every registered demo" do
      demo_entries = entries.select { |e| e[:kind] == "demo" }

      expect(demo_entries.size).to eq(TablerUi::Docs::DemoRegistry.all.size)
      expect(demo_entries.map { |e| e[:anchor] }.sort).to eq(TablerUi::Docs::DemoRegistry.all.map(&:slug).sort)
    end

    it "indexes every option of a rich component (table)" do
      table = TablerUi::Docs::DocParser.find("table")
      option_entries = entries.select { |e| e[:kind] == "option" && e[:component] == "table" }

      expect(table.options).not_to be_empty
      expect(option_entries.size).to eq(table.options.size)
      expect(option_entries.map { |e| e[:label] }).to match_array(table.options.map { |o| ":#{o.name}" })
    end

    it "indexes every section and example of a rich component (table)" do
      table = TablerUi::Docs::DocParser.find("table")

      section_entries = entries.select { |e| e[:kind] == "section" && e[:component] == "table" }
      example_entries = entries.select { |e| e[:kind] == "example" && e[:component] == "table" }

      expect(section_entries.size).to eq(table.sections.size)
      expect(example_entries.size).to eq(table.examples.size)
    end

    it "gives every entry the fields a search result needs to render and link" do
      entries.each do |entry|
        expect(entry.keys).to match_array(%i[kind label component context path anchor])
        expect(entry[:kind]).to be_a(String)
        expect(entry[:label]).to be_a(String)
        expect(entry[:label]).not_to be_empty
        expect(entry[:component]).to be_a(String)
        expect(entry[:context]).to be_a(String)
        expect(entry[:path]).to be_a(String)
      end
    end

    it "only demo entries carry an anchor -- component/section/option/example entries land at the top of the page" do
      entries.each do |entry|
        if entry[:kind] == "demo"
          expect(entry[:anchor]).to be_present
        else
          expect(entry[:anchor]).to be_nil
        end
      end
    end

    it "truncates :context to CONTEXT_LENGTH characters" do
      expect(entries).to be_none { |e| e[:context].length > described_class::CONTEXT_LENGTH }
    end

    it "every entry's :path resolves to a real, mounted route" do
      entries.map { |e| e[:path] }.uniq.each do |path|
        expect { Rails.application.routes.recognize_path(path, method: :get) }
          .not_to raise_error, "#{path.inspect} does not resolve to a real route"
      end
    end

    it "every :path points at the per-component docs page (component_path)" do
      route_helpers = TablerUi::Docs::Engine.routes.url_helpers

      entries.each do |entry|
        expect(entry[:path]).to eq(route_helpers.component_path(entry[:component]))
      end
    end
  end

  describe ".entries" do
    it "memoizes -- two calls return the exact same object" do
      expect(described_class.entries).to equal(described_class.entries)
    end

    it "rebuilds fresh content after #reset!" do
      first = described_class.entries
      described_class.reset!
      second = described_class.entries

      expect(second).not_to equal(first)
      expect(second).to eq(first)
    end

    it "does not require re-parsing to serve the same content twice (DocParser's own cache stays warm)" do
      described_class.entries

      expect(TablerUi::Docs::DocParser).not_to receive(:parse_file)
      described_class.reset!
      described_class.entries
    end
  end
end
