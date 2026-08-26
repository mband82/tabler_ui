# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"

# The design editor's page shell (GET /ui/editor, EditorController#show) and
# its sandboxed preview frame (GET /ui/editor/frame, EditorController#frame,
# see docs/app/views/layouts/tabler_ui/docs/editor_frame.html.erb). Both
# render static markup only -- no editor JS exists yet (another agent's
# work) -- so these specs only check the page shell itself: sidebar state,
# the values the not-yet-written Stimulus controller will read, and that the
# frame really is a separate, chrome-free document.
#
# See spec/lib/tabler_ui/docs/editor_endpoints_spec.rb for the JSON
# endpoints (#schema, #preview) this same controller also serves.
RSpec.describe "TablerUi::Docs design editor page", type: :request do
  describe "GET /ui/editor" do
    before { get "/ui/editor" }

    it "renders 200" do
      expect(response).to have_http_status(:ok)
    end

    it "appears in the sidebar's top list-group, above the component categories" do
      fragment = Nokogiri::HTML5.fragment(response.body)
      top_group = fragment.at_css("nav.docs-sidebar .list-group")

      expect(top_group).not_to be_nil
      expect(top_group.css("a").map(&:text)).to include("Design editor")
    end

    it "marks its own sidebar entry active, and nothing else" do
      fragment = Nokogiri::HTML5.fragment(response.body)
      links = fragment.at_css("nav.docs-sidebar").css("a")
      active = links.select { |a| a["class"].to_s.include?("active") }

      expect(active.map(&:text)).to eq(["Design editor"])
    end

    it "opens no component category (this page isn't a component)" do
      fragment = Nokogiri::HTML5.fragment(response.body)
      sidebar = fragment.at_css("nav.docs-sidebar")

      TablerUi::Docs::Navigation.category_names.each do |category|
        toggle = sidebar.css("button[data-bs-toggle='collapse']").find { |btn| btn.text.strip.start_with?(category) }
        target_id = toggle["data-bs-target"].delete_prefix("#")
        pane = sidebar.at_css("##{target_id}")

        expect(pane["class"]).not_to include("show")
      end
    end

    it "carries the schema/preview URLs and a CSRF token as Stimulus values on its root element" do
      root = Nokogiri::HTML5.fragment(response.body).at_css("#tabler-ui-docs-editor")

      expect(root).not_to be_nil
      expect(root["data-controller"]).to eq("tabler-ui--docs-editor")
      expect(root["data-tabler-ui--docs-editor-schema-url-value"]).to eq("/ui/editor/schema")
      expect(root["data-tabler-ui--docs-editor-preview-url-value"]).to eq("/ui/editor/preview")
      expect(root["data-tabler-ui--docs-editor-csrf-token-value"]).to be_present
    end

    it "embeds the preview iframe pointing at the frame endpoint" do
      iframe = Nokogiri::HTML5.fragment(response.body).at_css("iframe.docs-editor-frame")

      expect(iframe).not_to be_nil
      expect(iframe["src"]).to eq("/ui/editor/frame")
    end

    it "lists every component in the Components pane, grouped by category" do
      fragment = Nokogiri::HTML5.fragment(response.body)
      names = fragment.css(".docs-editor-palette-item").map { |el| el["data-component-name"] }

      expect(names).to match_array(TablerUi::Docs::Navigation.components)
    end
  end

  describe "GET /ui/editor/frame" do
    before { get "/ui/editor/frame" }

    it "renders 200" do
      expect(response).to have_http_status(:ok)
    end

    it "links the compiled component stylesheet, not the docs chrome stylesheet" do
      hrefs = Nokogiri::HTML5.fragment(response.body).css("link[rel='stylesheet']").map { |l| l["href"] }

      expect(hrefs.any? { |href| href.include?("tabler_ui_all") }).to be true
      expect(hrefs.any? { |href| href.include?("tabler_ui/docs") }).to be false
    end

    it "has no docs sidebar, navbar or search box -- it's a chrome-free document" do
      fragment = Nokogiri::HTML5.fragment(response.body)

      expect(fragment.at_css("nav.docs-sidebar")).to be_nil
      expect(fragment.at_css("header.navbar")).to be_nil
      expect(fragment.at_css(".docs-search")).to be_nil
    end

    it "renders exactly one canvas div for the editor's JS to write into" do
      fragment = Nokogiri::HTML5.fragment(response.body)

      expect(fragment.css("#tabler-ui-editor-canvas").size).to eq(1)
    end
  end
end
