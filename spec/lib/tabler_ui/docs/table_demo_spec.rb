# frozen_string_literal: true

require "rails_helper"

# TablerUi::Docs::TableDemoController backs the table component's one
# genuinely stateful demo -- docs/lib/tabler_ui/docs/demos/table_demos.rb's
# :sort_filter_page -- ported from ShowcaseController's TABLE_DEMO_* logic.
# See docs/DEMOS.md ("Stateful demos: locals:") for why the demo's `source:`
# itself cannot read params/route helpers, and TableDemoController's class
# docs for why this real GET endpoint exists at all.
#
# Exercised end to end against the mounted engine (spec/internal/config/routes.rb
# mounts it at "/ui"), verifying sorting, filtering and paging each work, that
# they preserve each other's params across links, and that junk params never
# 500 -- exactly the properties ShowcaseController's original methods were
# built to guarantee (see its table_demo_* comments).
RSpec.describe "TablerUi::Docs::TableDemoController", type: :request do
  def rows_order(body)
    Nokogiri::HTML5.fragment(body).css("tbody tr td:first-child").map(&:text)
  end

  def hrefs_for(body, selector)
    Nokogiri::HTML5.fragment(body).css(selector).map { |a| a["href"] }
  end

  def query_params(href)
    Rack::Utils.parse_nested_query(URI.parse(href).query)
  end

  describe "default (unsorted, unfiltered, page 1)" do
    it "renders 200 with the first page in original row order" do
      get "/ui/table_demo"

      expect(response).to have_http_status(:ok)
      expect(rows_order(response.body)).to eq(["Ada Lovelace", "Grace Hopper", "Alan Turing"])
    end
  end

  describe "sorting" do
    it "reorders rows ascending by the requested column" do
      get "/ui/table_demo", params: { sort: "name", dir: "asc" }

      expect(rows_order(response.body)).to eq(["Ada Lovelace", "Alan Turing", "Barbara Liskov"])
    end

    it "reorders rows descending" do
      get "/ui/table_demo", params: { sort: "name", dir: "desc" }

      expect(rows_order(response.body)).to eq(["Radia Perlman", "Margaret Hamilton", "Katherine Johnson"])
    end

    it "ignores a sort key outside the whitelist instead of raising" do
      get "/ui/table_demo", params: { sort: "zzz" }

      expect(response).to have_http_status(:ok)
      expect(rows_order(response.body)).to eq(["Ada Lovelace", "Grace Hopper", "Alan Turing"])
    end
  end

  describe "filtering" do
    it "filters by status" do
      get "/ui/table_demo", params: { status: "away" }

      expect(rows_order(response.body)).to contain_exactly("Alan Turing", "Radia Perlman")
    end

    it "filters by name (q), case-insensitively" do
      get "/ui/table_demo", params: { q: "ADA" }

      expect(rows_order(response.body)).to eq(["Ada Lovelace"])
    end
  end

  describe "paging" do
    it "returns the second page, distinct in order from a sorted page 1 with the same rows" do
      get "/ui/table_demo", params: { page: 2 }

      expect(rows_order(response.body)).to eq(["Katherine Johnson", "Margaret Hamilton", "Radia Perlman"])
    end

    it "clamps an out-of-range page to the last real page instead of raising" do
      get "/ui/table_demo", params: { page: 999 }

      expect(response).to have_http_status(:ok)
      expect(rows_order(response.body)).to eq(["Barbara Liskov"])
    end

    it "treats a non-numeric page as page 1 instead of raising" do
      get "/ui/table_demo", params: { page: "abc" }

      expect(response).to have_http_status(:ok)
      expect(rows_order(response.body)).to eq(["Ada Lovelace", "Grace Hopper", "Alan Turing"])
    end
  end

  describe "sort, filter and page composing and preserving each other" do
    it "sorts within the filtered set and pages the filtered+sorted result" do
      get "/ui/table_demo", params: { status: "active", sort: "name", dir: "asc" }

      # Active rows: Ada Lovelace, Grace Hopper, Katherine Johnson, Barbara Liskov (4)
      # sorted by name asc, page 1 (3 per page):
      expect(rows_order(response.body)).to eq(["Ada Lovelace", "Barbara Liskov", "Grace Hopper"])
    end

    it "keeps the status filter selected and carries it into the sort links' href" do
      get "/ui/table_demo", params: { status: "active" }

      selected = Nokogiri::HTML5.fragment(response.body).at_css('select[name="status"] option[selected]')
      expect(selected["value"]).to eq("active")

      sort_hrefs = hrefs_for(response.body, "a.table-sort")
      expect(sort_hrefs).not_to be_empty
      sort_hrefs.each do |href|
        expect(query_params(href)["status"]).to eq("active")
      end
    end

    it "carries the current sort into the pagination links' href, alongside the filter" do
      get "/ui/table_demo", params: { status: "active", sort: "name", dir: "asc" }

      page_hrefs = hrefs_for(response.body, "a.page-link")
      expect(page_hrefs).not_to be_empty
      page_hrefs.each do |href|
        params = query_params(href)
        expect(params["status"]).to eq("active")
        expect(params["sort"]).to eq("name")
        expect(params["dir"]).to eq("asc")
      end
    end

    it "carries the current sort into the filter toolbar's Reset link" do
      get "/ui/table_demo", params: { sort: "name", dir: "desc" }

      reset_link = Nokogiri::HTML5.fragment(response.body).css("a").find { |a| a.text.strip == "Reset" }

      expect(reset_link).not_to be_nil
      params = query_params(reset_link["href"])
      expect(params["sort"]).to eq("name")
      expect(params["dir"]).to eq("desc")
    end
  end

  describe "the filter form sits outside the frame, the pager sits inside it" do
    it "renders exactly one turbo-frame#table-demo, containing the pager but not the filter form" do
      get "/ui/table_demo"

      fragment = Nokogiri::HTML5.fragment(response.body)
      frame = fragment.at_css("turbo-frame#table-demo")

      expect(frame).not_to be_nil
      expect(frame.at_css("form")).to be_nil
      expect(frame.at_css("ul.pagination, nav")).not_to be_nil

      form = fragment.at_css("form")
      expect(form).not_to be_nil
      expect(frame.css("form")).to be_empty
    end
  end
end
