# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"

# The cross-cutting html: / <part>_html: reference page (GET
# /ui/html-attributes, PagesController#html_attributes) -- see
# docs/app/views/tabler_ui/docs/pages/html_attributes.html.erb. Component
# pages point here instead of restating the merge rule, so this spec asserts
# on the specific claims the page has to keep making (class appends,
# data/aria merge one level deep, everything else overwrites, callables,
# the no-element-to-attach-to case) rather than just checking it renders --
# a passing "renders 200" alone would let the page rot into a stub.
RSpec.describe "TablerUi::Docs HTML attributes page", type: :request do
  before { get "/ui/html-attributes" }

  it "renders 200" do
    expect(response).to have_http_status(:ok)
  end

  it "appears in the sidebar, above the component categories" do
    fragment = Nokogiri::HTML5.fragment(response.body)
    top_group = fragment.at_css("nav.docs-sidebar .list-group")

    expect(top_group).not_to be_nil
    expect(top_group.css("a").map(&:text)).to include("HTML attributes")
  end

  it "marks its own sidebar entry active, and no component or form_builder link" do
    fragment = Nokogiri::HTML5.fragment(response.body)
    links = fragment.at_css("nav.docs-sidebar").css("a")
    active = links.select { |a| a["class"].to_s.include?("active") }

    expect(active.map(&:text)).to eq(["HTML attributes"])
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

  it "explains the naming convention with a real component example" do
    expect(response.body).to include("html:")
    expect(response.body).to include("header_html:")
    expect(response.body).to include("body_html:")
    expect(response.body).to include("footer_html:")
  end

  it "states that class is appended, never replaced" do
    expect(response.body).to match(/appended/i)
    expect(response.body).to match(/never replaces/i)
  end

  it "states that data and aria merge one level deep" do
    expect(response.body).to match(/data.{0,80}merged one level deep/mi)
    expect(response.body).to match(/aria.{0,80}(same rule|one level deep)/mi)
  end

  it "states that every other attribute is overwritten by the caller's value" do
    expect(response.body).to match(/overwrites/i)
  end

  it "shows the button confirm:/html: worked example with both data keys surviving the merge" do
    expect(response.body).to include("turbo_confirm")
    expect(response.body).to include("testid")
  end

  it "documents callable per-item hooks with a real table row_html example" do
    expect(response.body).to include("row_html:")
    expect(response.body).to include("row.overdue?")
    expect(response.body).to include("html_for(:row")
  end

  it "documents that a hook is skipped when its element doesn't render" do
    expect(response.body).to include("link_html:")
    expect(response.body).to match(/silently\s+skipped/i)
  end

  it "links to the components whose real options it borrows as examples" do
    hrefs = Nokogiri::HTML5.fragment(response.body).css("a").map { |a| a["href"] }

    expect(hrefs).to include("/ui/components/card")
    expect(hrefs).to include("/ui/components/button")
    expect(hrefs).to include("/ui/components/table")
    expect(hrefs).to include("/ui/components/breadcrumb")
  end
end
