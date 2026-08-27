# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"

# The sidebar (docs/app/views/tabler_ui/docs/shared/_sidebar.html.erb) is
# rendered on every docs page via the layout -- this spec checks it lists
# every one of the 35 components (plus form_builder) and marks whichever one
# the current page is on as active.
RSpec.describe "TablerUi::Docs sidebar", type: :request do
  def sidebar_links(body)
    Nokogiri::HTML5.fragment(body).at_css("nav.docs-sidebar").css("a")
  end

  describe "present on every kind of docs page" do
    it "renders on the index" do
      get "/ui"

      expect(Nokogiri::HTML5.fragment(response.body).at_css("nav.docs-sidebar")).not_to be_nil
    end

    it "renders on a component page" do
      get "/ui/components/badge"

      expect(Nokogiri::HTML5.fragment(response.body).at_css("nav.docs-sidebar")).not_to be_nil
    end

    it "renders on the forms harness page" do
      get "/ui/forms"

      expect(Nokogiri::HTML5.fragment(response.body).at_css("nav.docs-sidebar")).not_to be_nil
    end
  end

  describe "listing" do
    it "links every one of the 35 real components, by their humanized title" do
      get "/ui/components/badge"

      links = sidebar_links(response.body)
      expected_titles = TablerUi::Docs::Navigation.components.map { |name| TablerUi::Docs::Navigation.title_for(name) }

      expect(links.map(&:text)).to include(*expected_titles)
    end

    it "links form_builder's own top-level entry, outside the categorized components" do
      get "/ui/components/badge"

      links = sidebar_links(response.body)
      expect(links.map(&:text)).to include("Form builder")
      expect(links.find { |a| a.text == "Form builder" }["href"]).to eq("/ui/forms")
    end

    it "links every category's components to their /ui/components/:name page" do
      get "/ui/components/badge"

      links = sidebar_links(response.body)
      href = links.find { |a| a.text == "Badge" }["href"]

      expect(href).to eq("/ui/components/badge")
    end

    # Used to be a top list-group entry alongside "Overview"/"HTML
    # attributes" -- now the top navbar's own "Editor" item is this page's
    # one link (see layout_chrome_spec.rb), so a second, sidebar-local link
    # to the exact same page would be pure duplication rather than a second
    # route to it.
    it "no longer links to the design editor -- the top navbar carries that link instead" do
      get "/ui/components/badge"

      links = sidebar_links(response.body)
      expect(links.map(&:text)).not_to include("Design editor")
    end
  end

  describe "marking the current page" do
    it "marks the current component's own link active, and no other component link" do
      get "/ui/components/badge"

      links = sidebar_links(response.body)
      active = links.select { |a| a["class"].to_s.include?("active") }

      expect(active.map(&:text)).to eq(["Badge"])
    end

    it "marks a different component's link active on that component's page" do
      get "/ui/components/modal"

      links = sidebar_links(response.body)
      active = links.select { |a| a["class"].to_s.include?("active") }

      expect(active.map(&:text)).to eq(["Modal"])
    end

    it "marks 'Overview' active on the index, with no component link active" do
      get "/ui"

      links = sidebar_links(response.body)
      active = links.select { |a| a["class"].to_s.include?("active") }

      expect(active.map(&:text)).to eq(["Overview"])
    end

    it "marks 'Form builder' active on the forms harness page" do
      get "/ui/forms"

      links = sidebar_links(response.body)
      active = links.select { |a| a["class"].to_s.include?("active") }

      expect(active.map(&:text)).to eq(["Form builder"])
    end
  end

  # Each category is now a Bootstrap collapse pane (data-bs-toggle="collapse"
  # + data-controller="tabler-ui--collapse" on the pane itself), the same
  # machinery app/components/tabler_ui/accordion/_component.html.erb drives
  # -- reused, not reinvented (rule 6). Collapsed panes stay in the DOM (CSS
  # -hidden only), so every "listing"/"marking the current page" example
  # above still passes unmodified -- Nokogiri finds every link regardless
  # of which pane it's nested in.
  describe "collapsible categories" do
    def toggle_for(sidebar, category)
      sidebar.css("button[data-bs-toggle='collapse']").find { |btn| btn.text.strip.start_with?(category) }
    end

    def pane_for(sidebar, toggle)
      target_id = toggle["data-bs-target"].delete_prefix("#")
      sidebar.at_css("##{target_id}")
    end

    it "wraps every category, and Forms, in a real Bootstrap collapse pane driven by the collapse controller" do
      get "/ui/components/badge"

      sidebar = Nokogiri::HTML5.fragment(response.body).at_css("nav.docs-sidebar")

      (TablerUi::Docs::Navigation.category_names + ["Forms"]).each do |category|
        toggle = toggle_for(sidebar, category)
        expect(toggle).not_to be_nil, "expected a collapse toggle button for #{category}"

        pane = pane_for(sidebar, toggle)
        expect(pane).not_to be_nil
        expect(pane["class"]).to include("collapse")
        expect(pane["data-controller"]).to eq("tabler-ui--collapse")
      end
    end

    it "keeps Forms' pane closed by default when it isn't the current page" do
      get "/ui/components/badge"

      sidebar = Nokogiri::HTML5.fragment(response.body).at_css("nav.docs-sidebar")
      toggle = toggle_for(sidebar, "Forms")
      pane = pane_for(sidebar, toggle)

      expect(pane["class"]).not_to include("show")
      expect(toggle["aria-expanded"]).to eq("false")
    end

    it "opens Forms' pane, and no category pane, on the forms harness page" do
      get "/ui/forms"

      sidebar = Nokogiri::HTML5.fragment(response.body).at_css("nav.docs-sidebar")

      forms_toggle = toggle_for(sidebar, "Forms")
      forms_pane = pane_for(sidebar, forms_toggle)
      expect(forms_pane["class"]).to include("show")
      expect(forms_toggle["aria-expanded"]).to eq("true")
      expect(forms_toggle["class"]).not_to include("collapsed")

      TablerUi::Docs::Navigation.category_names.each do |category|
        toggle = toggle_for(sidebar, category)
        pane = pane_for(sidebar, toggle)

        expect(pane["class"]).not_to include("show")
        expect(toggle["aria-expanded"]).to eq("false")
      end
    end

    it "opens the current component's own category, server-side, and no other" do
      get "/ui/components/badge"

      sidebar = Nokogiri::HTML5.fragment(response.body).at_css("nav.docs-sidebar")
      badge_category = TablerUi::Docs::Navigation.category_for("badge")

      TablerUi::Docs::Navigation.category_names.each do |category|
        toggle = toggle_for(sidebar, category)
        pane = pane_for(sidebar, toggle)

        if category == badge_category
          expect(pane["class"]).to include("show")
          expect(toggle["aria-expanded"]).to eq("true")
          expect(toggle["class"]).not_to include("collapsed")
        else
          expect(pane["class"]).not_to include("show")
          expect(toggle["aria-expanded"]).to eq("false")
          expect(toggle["class"]).to include("collapsed")
        end
      end
    end

    it "opens no category at all on the index (no current component)" do
      get "/ui"

      sidebar = Nokogiri::HTML5.fragment(response.body).at_css("nav.docs-sidebar")

      TablerUi::Docs::Navigation.category_names.each do |category|
        toggle = toggle_for(sidebar, category)
        pane = pane_for(sidebar, toggle)

        expect(pane["class"]).not_to include("show")
        expect(toggle["aria-expanded"]).to eq("false")
      end
    end
  end
end
