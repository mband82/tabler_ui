# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TablerUi::Table", type: :component do
  it "renders with no arguments at all" do
    fragment = component_fragment(:table)

    expect(fragment.css("table")).not_to be_empty
    expect(fragment.css("thead")).not_to be_empty
    expect(fragment.css("tbody tr")).to be_empty
  end

  it "renders columns and data, invoking each column's :value callable per row" do
    columns = [
      { label: "Name", value: ->(row) { row[:name] } },
      { label: "Age", value: ->(row) { row[:age].to_s } },
    ]
    data = [{ name: "Ada", age: 36 }, { name: "Grace", age: 85 }]

    fragment = component_fragment(:table, columns: columns, data: data)

    headers = fragment.css("thead th").map(&:text)
    expect(headers).to eq(%w[Name Age])

    rows = fragment.css("tbody tr")
    expect(rows.size).to eq(2)
    expect(rows[0].css("td").map(&:text)).to eq(%w[Ada 36])
    expect(rows[1].css("td").map(&:text)).to eq(%w[Grace 85])
  end

  it "renders a table with a head and no body rows for an empty data:, without raising" do
    columns = [{ label: "Name", value: ->(row) { row[:name] } }]

    expect do
      fragment = component_fragment(:table, columns: columns, data: [])

      expect(fragment.css("thead th").map(&:text)).to eq(["Name"])
      expect(fragment.css("tbody tr")).to be_empty
    end.not_to raise_error
  end

  it_behaves_like "an element with an html hook", :table, {},
    hook: :html, selector: ".card"

  it_behaves_like "an element with an html hook", :table, {},
    hook: :table_html, selector: "table"

  # thead/tbody carry no base class of their own in Tabler's markup, so the
  # shared example's "component class survives alongside the caller's" check
  # (which asserts more than one class ends up on the element) doesn't fit --
  # hand-written instead.
  it "passes id/data/class through thead_html: onto the <thead>" do
    fragment = component_fragment(:table, thead_html: { class: "hook-extra-class", id: "hook-test-id",
                                                          data: { testid: "hook-test-data" } })
    element = fragment.css("thead").first

    expect(element).not_to be_nil
    expect(element["class"].to_s.split(/\s+/)).to include("hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it "passes id/data/class through tbody_html: onto the <tbody>" do
    fragment = component_fragment(:table, tbody_html: { class: "hook-extra-class", id: "hook-test-id",
                                                          data: { testid: "hook-test-data" } })
    element = fragment.css("tbody").first

    expect(element).not_to be_nil
    expect(element["class"].to_s.split(/\s+/)).to include("hook-extra-class")
    expect(element["id"]).to eq("hook-test-id")
    expect(element["data-testid"]).to eq("hook-test-data")
  end

  it "applies row_html: as a plain Hash to every row (appending to the row's own class)" do
    columns = [{ label: "Name", value: ->(row) { row[:name] } }]
    data = [{ name: "Ada" }, { name: "Grace" }]

    fragment = component_fragment(:table, columns: columns, data: data,
                                           row_html: { class: "all-rows" })
    rows = fragment.css("tbody tr")

    expect(rows.size).to eq(2)
    rows.each { |row| expect(row["class"].to_s.split(/\s+/)).to include("all-rows") }
  end

  it "applies row_html: as a callable per row, so rows can differ" do
    columns = [{ label: "Name", value: ->(row) { row[:name] } }]
    data = [{ name: "Ada", overdue: true }, { name: "Grace", overdue: false }]

    fragment = component_fragment(
      :table, columns: columns, data: data,
              row_html: ->(row) { row[:overdue] ? { class: "table-danger" } : {} }
    )
    rows = fragment.css("tbody tr")

    expect(rows[0]["class"].to_s.split(/\s+/)).to include("table-danger")
    expect(rows[1]["class"].to_s).not_to include("table-danger")
  end

  it "appends a per-column :class to the cell's base class instead of replacing it" do
    columns = [{ label: "Name", class: "text-end", value: ->(row) { row[:name] } }]
    data = [{ name: "Ada" }]

    fragment = component_fragment(:table, columns: columns, data: data)

    th = fragment.css("thead th").first
    td = fragment.css("tbody td").first

    expect(th["class"].to_s.split(/\s+/)).to include("text-end")
    expect(td["class"].to_s.split(/\s+/)).to include("text-end")
  end

  it "adds table-striped for striped: true" do
    fragment = component_fragment(:table, striped: true)

    expect(fragment.css("table").first["class"].split(/\s+/)).to include("table-striped")
  end

  it "adds table-hover for hover: true" do
    fragment = component_fragment(:table, hover: true)

    expect(fragment.css("table").first["class"].split(/\s+/)).to include("table-hover")
  end

  it "adds table-bordered for bordered: true" do
    fragment = component_fragment(:table, bordered: true)

    expect(fragment.css("table").first["class"].split(/\s+/)).to include("table-bordered")
  end

  it "adds table-sm for sm: true" do
    fragment = component_fragment(:table, sm: true)

    expect(fragment.css("table").first["class"].split(/\s+/)).to include("table-sm")
  end

  it "adds table-nowrap for nowrap: true" do
    fragment = component_fragment(:table, nowrap: true)

    expect(fragment.css("table").first["class"].split(/\s+/)).to include("table-nowrap")
  end

  it "adds table-vcenter for vcenter: true" do
    fragment = component_fragment(:table, vcenter: true)

    expect(fragment.css("table").first["class"].split(/\s+/)).to include("table-vcenter")
  end

  it "wraps the table in a .card by default" do
    fragment = component_fragment(:table)

    expect(fragment.css(".card")).not_to be_empty
    expect(fragment.css(".card .table-responsive table")).not_to be_empty
  end

  it "omits the .card wrapper for card: false" do
    fragment = component_fragment(:table, card: false)

    expect(fragment.css(".card")).to be_empty
    expect(fragment.css(".table-responsive table")).not_to be_empty
  end
end
