# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/search_index"

# The JSON endpoint backing the docs engine's full-text search: GET
# /ui/search (spec/internal/config/routes.rb mounts TablerUi::Docs::Engine
# at "/ui", docs/config/routes.rb maps "search" -> SearchController#index).
# Mirrors the request-spec pattern already used for the forms harness
# (spec/requests/tabler_ui/docs/forms_spec.rb) and the engine itself
# (spec/lib/tabler_ui/docs/engine_spec.rb).
RSpec.describe "TablerUi::Docs Search", type: :request do
  describe "GET /ui/search" do
    before { get "/ui/search" }

    it "renders 200" do
      expect(response).to have_http_status(:ok)
    end

    it "renders JSON" do
      expect(response.media_type).to eq("application/json")
    end

    it "returns every SearchIndex entry, single-sourced against the same module" do
      body = JSON.parse(response.body)

      expect(body.size).to eq(TablerUi::Docs::SearchIndex.entries.size)
    end

    it "returns entries shaped the way the search UI expects" do
      body = JSON.parse(response.body)
      first = body.first

      expect(first.keys).to match_array(%w[kind label component context path anchor])
    end

    it "includes a demo entry with its anchor" do
      body = JSON.parse(response.body)
      demo = body.find { |e| e["kind"] == "demo" }

      expect(demo).not_to be_nil
      expect(demo["anchor"]).to be_present
    end

    it "includes a component entry for table" do
      body = JSON.parse(response.body)
      table_component = body.find { |e| e["kind"] == "component" && e["component"] == "table" }

      expect(table_component).not_to be_nil
      expect(table_component["path"]).to eq("/ui/components/table")
    end
  end
end
