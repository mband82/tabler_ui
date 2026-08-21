# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"
require "tabler_ui/docs/doc_parser"

# The per-component documentation page: GET /ui/components/:name (see
# docs/config/routes.rb -> ComponentsController -> components/show.html.erb).
# Combines the generated API reference (DocParser) with the curated live-demo
# corpus (DemoRegistry) for one component.
RSpec.describe "TablerUi::Docs component pages", type: :request do
  # The sweep this task exists to have: every one of the 35 real components
  # (Navigation.components, not a hardcoded list -- so a 36th component added
  # later is covered automatically) must render its page without error. This
  # is the net that catches a component whose parsed docs or demos happen to
  # break the shared template.
  describe "every real component" do
    TablerUi::Docs::Navigation.components.each do |name|
      it "renders /ui/components/#{name} as 200" do
        get "/ui/components/#{name}"

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "an unknown component name" do
    it "renders 404 rather than raising" do
      get "/ui/components/not_a_real_component"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a component with no demos (dark_mode_toggle)" do
    it "renders 200 with a plain fallback instead of a broken-looking empty section" do
      expect(TablerUi::Docs::DemoRegistry.for(:dark_mode_toggle)).to eq([])

      get "/ui/components/dark_mode_toggle"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No demos registered for <code>dark_mode_toggle</code>")
    end
  end

  describe "options table -- table, the rich case (29 @option rows)" do
    it "renders one row per parsed option, including angle-bracket types escaped correctly" do
      parsed = TablerUi::Docs::DocParser.find("table")
      expect(parsed.options.size).to be >= 20 # table currently has 29; guard against a future regression to a handful

      get "/ui/components/table"
      expect(response).to have_http_status(:ok)

      fragment = Nokogiri::HTML5.fragment(response.body)
      rows = fragment.css("table#component-options tbody tr")
      expect(rows.size).to eq(parsed.options.size)

      option_names = rows.map { |row| row.at_css("td:first-child").text.strip }
      expect(option_names).to include(*parsed.options.map(&:name))

      # "Array<Hash>" (the :columns option's type) round-trips through HTML
      # escaping (tag.td / badge's `text:` both auto-escape) and back out as
      # its literal self once Nokogiri decodes the entities -- proves the
      # angle brackets survived rather than being swallowed as a stray tag.
      types = rows.map { |row| row.at_css("td:nth-child(2)").text.strip }
      expect(types).to include("Array<Hash>")
    end
  end

  describe "a component with sparse/no parsed docs" do
    it "still renders 200 with explicit fallback text rather than an empty-looking page" do
      # icon has no `def initialize` @option block in the conventional class
      # doc parse (parsed via DocParser directly -- proves the page's option
      # fallback text is exercised, not just its "documented" branch).
      allow(TablerUi::Docs::DocParser).to receive(:find).and_call_original
      allow(TablerUi::Docs::DocParser).to receive(:find).with("icon")
                                                         .and_return(TablerUi::Docs::ParsedComponent.new("icon"))

      get "/ui/components/icon"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No description parsed for <code>icon</code> yet.")
      expect(response.body).to include("No documented options for <code>icon</code> yet.")
    end
  end

  # CRITICAL: @example blocks are illustrative only (User.all, users_path,
  # @pagy.page -- none of which exist in this dummy app). They must render as
  # inert, escaped text -- never through `render inline:` -- see
  # ParsedComponent's class docs and components/show.html.erb's own comment.
  describe "@example blocks render inert, never executed" do
    it "prints table's 'Basic usage' example (which references User.all) as escaped text, and the page still renders 200" do
      example = TablerUi::Docs::DocParser.find("table").examples.find { |e| e.code.include?("User.all") }
      expect(example).not_to be_nil # guards the premise: this example still exists and still references User.all

      get "/ui/components/table"

      expect(response).to have_http_status(:ok) # would 500 if `render inline:` had actually tried to call User.all here

      # The example's raw ERB never appears unescaped, but its escaped form
      # does -- built from the parsed example's own code, not a hand-copied
      # guess, so this doesn't rot if the doc comment's wording/wrapping ever
      # changes.
      expect(response.body).not_to include(example.code)
      expect(response.body).to include(ERB::Util.html_escape(example.code))

      fragment = Nokogiri::HTML5.fragment(response.body)
      printed = fragment.css("pre code").map(&:text)
      expect(printed).to include(a_string_including("User.all"))
    end
  end
end
