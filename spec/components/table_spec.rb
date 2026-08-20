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

  it_behaves_like "an element with an html hook", :table,
    { columns: [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }],
      sort_url: ->(key, dir) { "/x?sort=#{key}&dir=#{dir}" } },
    hook: :sort_html, selector: "a.table-sort"

  it_behaves_like "an element with an html hook", :table, { filter: { fields: [{ name: "q" }] } },
    hook: :filter_html, selector: ".card-body"

  it_behaves_like "an element with an html hook", :table, { filter: { fields: [{ name: "q" }] } },
    hook: :filter_form_html, selector: "form"

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

  describe "responsive:" do
    it "defaults to plain table-responsive on the wrapper, and no data-label on cells" do
      columns = [{ label: "Name", value: ->(row) { row[:name] } }]
      fragment = component_fragment(:table, columns: columns, data: [{ name: "Ada" }])

      expect(fragment.css(".table-responsive")).not_to be_empty
      expect(fragment.css("td[data-label]")).to be_empty
    end

    TablerUi::Breakpoint::ALL.each do |breakpoint|
      it "responsive: #{breakpoint.inspect} emits table-responsive-#{breakpoint} and not plain table-responsive" do
        fragment = component_fragment(:table, responsive: breakpoint)

        wrapper = fragment.css(".card .table-responsive-#{breakpoint}")
        expect(wrapper).not_to be_empty

        classes = wrapper.first["class"].split(/\s+/)
        expect(classes).to include("table-responsive-#{breakpoint}")
        expect(classes).not_to include("table-responsive")
      end
    end

    it "raises ArgumentError for an invalid breakpoint" do
      expect {
        component_fragment(:table, responsive: "huge")
      }.to raise_error(ArgumentError, /unknown breakpoint/)
    end

    it "responsive: false emits neither class, with card: true" do
      fragment = component_fragment(:table, responsive: false)

      expect(fragment.css(".card")).not_to be_empty
      expect(fragment.css(".table-responsive")).to be_empty
      expect(fragment.css("[class*='table-responsive-']")).to be_empty
    end

    it "responsive: false emits neither class, with card: false" do
      fragment = component_fragment(:table, responsive: false, card: false)

      expect(fragment.css(".table-responsive")).to be_empty
      expect(fragment.css("[class*='table-responsive-']")).to be_empty
      expect(fragment.css("table")).not_to be_empty
    end
  end

  describe "mobile:" do
    let(:columns) do
      [
        { label: "Name", value: ->(row) { row[:name] } },
        { label: "Age", value: ->(row) { row[:age].to_s } },
      ]
    end
    let(:data) { [{ name: "Ada", age: 36 }, { name: "Grace", age: 85 }] }

    it "mobile: true puts table-mobile on the <table>, not on the wrapper" do
      fragment = component_fragment(:table, columns: columns, data: data, mobile: true)

      table_el = fragment.css("table").first
      expect(table_el["class"].split(/\s+/)).to include("table-mobile")
      expect(fragment.css(".table-responsive")[0]["class"].split(/\s+/)).not_to include("table-mobile")
    end

    it "mobile: true gives every <td> a data-label matching its column, aligned by position" do
      fragment = component_fragment(:table, columns: columns, data: data, mobile: true)

      rows = fragment.css("tbody tr")
      expect(rows.size).to eq(2)

      rows.each do |row|
        cells = row.css("td")
        expect(cells.map { |td| td["data-label"] }).to eq(%w[Name Age])
      end
    end

    it "mobile: true does not add data-label to <th> cells" do
      fragment = component_fragment(:table, columns: columns, data: data, mobile: true)

      expect(fragment.css("thead th[data-label]")).to be_empty
    end

    TablerUi::Breakpoint::ALL.each do |breakpoint|
      it "mobile: #{breakpoint.inspect} emits table-mobile-#{breakpoint} on the <table>" do
        fragment = component_fragment(:table, mobile: breakpoint)

        classes = fragment.css("table").first["class"].split(/\s+/)
        expect(classes).to include("table-mobile-#{breakpoint}")
        expect(classes).not_to include("table-mobile")
      end
    end

    it "raises ArgumentError for an invalid breakpoint" do
      expect {
        component_fragment(:table, mobile: "huge")
      }.to raise_error(ArgumentError, /unknown breakpoint/)
    end

    it "omits data-label for a column with a nil label, but still labels the others" do
      columns_with_blank = [
        { label: nil, value: ->(row) { row[:actions] } },
        { label: "Name", value: ->(row) { row[:name] } },
      ]
      data_rows = [{ actions: "edit", name: "Ada" }]

      fragment = component_fragment(:table, columns: columns_with_blank, data: data_rows, mobile: true)
      cells = fragment.css("tbody tr").first.css("td")

      expect(cells[0].attribute("data-label")).to be_nil
      expect(cells[1]["data-label"]).to eq("Name")
    end

    it "omits data-label for a column with a blank string label" do
      columns_with_blank = [{ label: "", value: ->(row) { row[:name] } }]
      data_rows = [{ name: "Ada" }]

      fragment = component_fragment(:table, columns: columns_with_blank, data: data_rows, mobile: true)

      expect(fragment.css("tbody td").first.attribute("data-label")).to be_nil
    end

    it "combines with responsive: and the boolean style modifiers" do
      fragment = component_fragment(:table, columns: columns, data: data,
                                             mobile: "md", responsive: "lg", striped: true, hover: true)

      table_el = fragment.css("table").first
      classes = table_el["class"].split(/\s+/)

      expect(classes).to include("table-mobile-md", "table-striped", "table-hover")
      expect(fragment.css(".table-responsive-lg")).not_to be_empty
      expect(fragment.css("tbody td").first["data-label"]).to eq("Name")
    end
  end

  describe "sort:" do
    let(:sort_calls) { [] }
    let(:sort_url) do
      lambda do |key, dir|
        sort_calls << [key, dir]
        "/x?sort=#{key}&dir=#{dir}"
      end
    end

    it "renders a plain <th> with no <a> for a column with no sort: (unchanged behaviour)" do
      columns = [{ label: "Name", value: ->(row) { row[:name] } }]
      fragment = component_fragment(:table, columns: columns)

      th = fragment.css("thead th").first
      expect(th.css("a")).to be_empty
      expect(th.text).to eq("Name")
    end

    it "renders th > a.table-sort with href equal to whatever sort_url: returned" do
      columns = [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }]
      fragment = component_fragment(:table, columns: columns, sort_url: sort_url)

      link = fragment.css("thead th a.table-sort").first
      expect(link).not_to be_nil
      expect(link["href"]).to eq("/x?sort=name&dir=asc")
    end

    it "marks the currently-sorted column with aria-sort and an asc/desc class, leaving a different sortable column untouched" do
      columns = [
        { label: "Name", sort: :name, value: ->(row) { row[:name] } },
        { label: "Age", sort: :age, value: ->(row) { row[:age].to_s } },
      ]
      fragment = component_fragment(:table, columns: columns, sort: { key: :name, dir: :asc }, sort_url: sort_url)

      name_th, age_th = fragment.css("thead th")

      expect(name_th["aria-sort"]).to eq("ascending")
      expect(name_th.css("a").first["class"].split(/\s+/)).to include("asc")

      expect(age_th["aria-sort"]).to be_nil
      age_classes = age_th.css("a").first["class"].split(/\s+/)
      expect(age_classes).not_to include("asc")
      expect(age_classes).not_to include("desc")
    end

    it "sets aria-sort to descending, and the asc/desc class to desc, when sorted :desc" do
      columns = [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }]
      fragment = component_fragment(:table, columns: columns, sort: { key: :name, dir: :desc }, sort_url: sort_url)

      th = fragment.css("thead th").first
      expect(th["aria-sort"]).to eq("descending")
      expect(th.css("a").first["class"].split(/\s+/)).to include("desc")
    end

    describe "direction cycle" do
      let(:columns) { [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }] }

      it "an unsorted sortable column links to dir :asc" do
        component_fragment(:table, columns: columns, sort_url: sort_url)
        expect(sort_calls).to eq([[:name, :asc]])
      end

      it "a column currently sorted :asc links to dir :desc" do
        component_fragment(:table, columns: columns, sort: { key: :name, dir: :asc }, sort_url: sort_url)
        expect(sort_calls).to eq([[:name, :desc]])
      end

      it "a column currently sorted :desc links to dir :asc by default" do
        component_fragment(:table, columns: columns, sort: { key: :name, dir: :desc }, sort_url: sort_url)
        expect(sort_calls).to eq([[:name, :asc]])
      end

      it "a column currently sorted :desc links to dir nil with sort_reset: true" do
        component_fragment(:table, columns: columns, sort: { key: :name, dir: :desc },
                                    sort_url: sort_url, sort_reset: true)
        expect(sort_calls).to eq([[:name, nil]])
      end
    end

    it "sort: { key: } with no dir: defaults to sorting :asc" do
      columns = [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }]
      fragment = component_fragment(:table, columns: columns, sort: { key: :name }, sort_url: sort_url)

      expect(fragment.css("thead th").first["aria-sort"]).to eq("ascending")
    end

    it "matches sort key string/symbol-tolerantly -- a String sort: { key: } matches a Symbol column sort:" do
      columns = [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }]
      fragment = component_fragment(:table, columns: columns, sort: { key: "name" }, sort_url: sort_url)

      expect(fragment.css("thead th").first["aria-sort"]).to eq("ascending")
    end

    it "raises ArgumentError for an unknown sort: { dir: }" do
      expect {
        component_fragment(:table, sort: { key: :name, dir: :bogus }, sort_url: sort_url)
      }.to raise_error(ArgumentError, /dir/i)
    end

    it "raises ArgumentError when a column has sort: but no sort_url: is given" do
      columns = [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }]

      expect {
        component_fragment(:table, columns: columns)
      }.to raise_error(ArgumentError, /sort_url/)
    end

    it "REGRESSION: a column with an explicit sort: nil is not sortable and does not require sort_url:" do
      expect {
        fragment = component_fragment(:table, columns: [{ label: "X", sort: nil, value: ->(row) { "" } }])

        th = fragment.css("thead th").first
        expect(th.css("a")).to be_empty
      }.not_to raise_error
    end

    it "keeps the column's own :class on the <th>, never on the <a>, for a sortable column" do
      columns = [{ label: "Name", sort: :name, class: "text-end", value: ->(row) { row[:name] } }]
      fragment = component_fragment(:table, columns: columns, sort_url: sort_url)

      th = fragment.css("thead th").first
      a = th.css("a").first

      expect(th["class"].to_s.split(/\s+/)).to include("text-end")
      expect(a["class"].to_s.split(/\s+/)).not_to include("text-end")
    end

    it "applies sort_html: as a callable per column, so columns can differ" do
      columns = [
        { label: "Name", sort: :name, value: ->(row) { row[:name] } },
        { label: "Age", sort: :age, value: ->(row) { row[:age].to_s } },
      ]
      fragment = component_fragment(
        :table, columns: columns, sort_url: sort_url,
                sort_html: ->(col) { col[:sort] == :name ? { class: "hook-a" } : { class: "hook-b" } }
      )
      name_link, age_link = fragment.css("a.table-sort")

      expect(name_link["class"].split(/\s+/)).to include("hook-a")
      expect(age_link["class"].split(/\s+/)).to include("hook-b")
    end
  end

  describe "filter:" do
    it "renders no <form> at all when filter: is not given, table markup unaffected" do
      columns = [{ label: "Name", value: ->(row) { row[:name] } }]
      fragment = component_fragment(:table, columns: columns, data: [{ name: "Ada" }])

      expect(fragment.css("form")).to be_empty
      expect(fragment.css("table")).not_to be_empty
      expect(fragment.css("tbody td").map(&:text)).to eq(["Ada"])
    end

    it "renders search/text/date fields as <input class=form-control> with the matching type" do
      fragment = component_fragment(
        :table, filter: {
          fields: [
            { name: "q", type: :search },
            { name: "title", type: :text },
            { name: "from", type: :date },
          ]
        }
      )

      inputs = fragment.css("input.form-control")
      expect(inputs.map { |i| i["type"] }).to contain_exactly("search", "text", "date")
    end

    it "renders a :select field as <select class=form-select> with the right options" do
      fragment = component_fragment(
        :table, filter: { fields: [{ name: "status", type: :select, options: %w[active inactive] }] }
      )

      select = fragment.css("select.form-select").first
      expect(select).not_to be_nil

      options = select.css("option")
      expect(options.map(&:text)).to eq(%w[active inactive])
      expect(options.map { |o| o["value"] }).to eq(%w[active inactive])
    end

    it "select :options accepts both [label, value] pairs and plain strings (label == value)" do
      fragment = component_fragment(
        :table, filter: { fields: [{ name: "status", type: :select, options: [["Active", "1"], "inactive"] }] }
      )
      options = fragment.css("select option")

      expect(options[0].text).to eq("Active")
      expect(options[0]["value"]).to eq("1")
      expect(options[1].text).to eq("inactive")
      expect(options[1]["value"]).to eq("inactive")
    end

    it "select include_blank: true renders a blank-labelled option with value=''" do
      fragment = component_fragment(
        :table, filter: { fields: [{ name: "status", type: :select, options: %w[active], include_blank: true }] }
      )
      blank = fragment.css("select option").first

      expect(blank.text).to eq("")
      expect(blank["value"]).to eq("")
    end

    it "select include_blank: 'All' renders a labelled blank option" do
      fragment = component_fragment(
        :table,
        filter: { fields: [{ name: "status", type: :select, options: %w[active], include_blank: "All" }] }
      )
      blank = fragment.css("select option").first

      expect(blank.text).to eq("All")
      expect(blank["value"]).to eq("")
    end

    it "label: renders label.form-label whose for matches the rendered input's id" do
      fragment = component_fragment(:table, filter: { fields: [{ name: "q", label: "Search" }] })

      label = fragment.css("label.form-label").first
      input = fragment.css("input").first

      expect(label.text).to eq("Search")
      expect(label["for"]).to eq(input["id"])
    end

    it "hidden: renders a hidden input per entry, skipping nil/blank values" do
      fragment = component_fragment(:table, filter: { hidden: { sort: "name", dir: "", empty: nil } })
      hidden_inputs = fragment.css("input[type=hidden]")

      expect(hidden_inputs.size).to eq(1)
      expect(hidden_inputs.first["name"]).to eq("sort")
      expect(hidden_inputs.first["value"]).to eq("name")
    end

    describe "method:/auto:" do
      it "method: :get (default) auto-submits via Stimulus and renders no Apply button" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }] })
        form = fragment.css("form").first

        expect(form["data-controller"]).to eq("tabler-ui--filter")
        expect(form["data-action"]).to include("input->tabler-ui--filter#submit")
        expect(form["data-action"]).to include("change->tabler-ui--filter#submit")
        expect(fragment.css(".btn.btn-primary")).to be_empty
      end

      it "method: :post renders an Apply button and no Stimulus wiring on the form" do
        fragment = component_fragment(:table, filter: { method: :post, fields: [{ name: "q" }] })
        form = fragment.css("form").first

        expect(form["data-controller"]).to be_nil
        button = fragment.css("button.btn.btn-primary").first
        expect(button).not_to be_nil
        expect(button["type"]).to eq("submit")
      end

      it "method: :get, auto: false overrides the default -- Apply button renders, no Stimulus wiring" do
        fragment = component_fragment(:table, filter: { method: :get, auto: false, fields: [{ name: "q" }] })
        form = fragment.css("form").first

        expect(form["data-controller"]).to be_nil
        expect(fragment.css("button.btn.btn-primary")).not_to be_empty
      end

      it "method: :post, auto: true overrides the default -- no Apply button, Stimulus wiring present" do
        fragment = component_fragment(:table, filter: { method: :post, auto: true, fields: [{ name: "q" }] })
        form = fragment.css("form").first

        expect(form["data-controller"]).to eq("tabler-ui--filter")
        expect(fragment.css(".btn.btn-primary")).to be_empty
      end
    end

    it "debounce: 500 renders as data-tabler-ui--filter-debounce-value on the form" do
      fragment = component_fragment(:table, filter: { debounce: 500, fields: [{ name: "q" }] })

      expect(fragment.css("form").first["data-tabler-ui--filter-debounce-value"]).to eq("500")
    end

    it "reset: renders a.btn.btn-link with the Reset label and href" do
      fragment = component_fragment(:table, filter: { reset: "/some/url", fields: [{ name: "q" }] })
      link = fragment.css("a.btn.btn-link").first

      expect(link).not_to be_nil
      expect(link["href"]).to eq("/some/url")
    end

    it "submit: overrides the Apply button's text" do
      fragment = component_fragment(:table, filter: { method: :post, submit: "Go", fields: [{ name: "q" }] })

      expect(fragment.css("button.btn.btn-primary").first.text).to eq("Go")
    end

    it "col: on a field overrides its wrapper div's class outright" do
      fragment = component_fragment(:table, filter: { fields: [{ name: "q", col: "col-6" }] })
      wrapper = fragment.css("input").first.parent

      expect(wrapper["class"]).to eq("col-6")
    end

    it "raises ArgumentError for a field missing name:" do
      expect {
        component_fragment(:table, filter: { fields: [{ type: :search }] })
      }.to raise_error(ArgumentError, /name/)
    end

    it "raises ArgumentError for an unknown field type:" do
      expect {
        component_fragment(:table, filter: { fields: [{ name: "q", type: :bogus }] })
      }.to raise_error(ArgumentError, /type/)
    end

    it "raises ArgumentError for an unknown filter: { method: }" do
      expect {
        component_fragment(:table, filter: { method: :put, fields: [{ name: "q" }] })
      }.to raise_error(ArgumentError, /method/)
    end

    it "card: false renders the filter's outer div as a sibling .mb-3 before .table-responsive, with no .card anywhere" do
      fragment = component_fragment(:table, card: false, filter: { fields: [{ name: "q" }] })

      expect(fragment.css(".card")).to be_empty
      expect(fragment.css(".card-body")).to be_empty
      expect(fragment.css(".mb-3")).not_to be_empty
      expect(fragment.css(".mb-3 + .table-responsive")).not_to be_empty
    end

    describe "REGRESSION: deterministic field ids" do
      it "renders the same id across two identical renders" do
        opts = { filter: { fields: [{ name: "q" }] } }

        fragment1 = component_fragment(:table, **opts)
        fragment2 = component_fragment(:table, **opts)

        id1 = fragment1.css("input").first["id"]
        id2 = fragment2.css("input").first["id"]

        expect(id1).to eq(id2)
        expect(id1).to eq("table-filter-q")
      end

      it "an explicit id: on a field overrides the generated table-filter-q id" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q", id: "custom-id" }] })

        expect(fragment.css("input").first["id"]).to eq("custom-id")
      end
    end
  end

  describe "filter slot:" do
    it "renders the slot's content inside the <form>" do
      fragment = component_fragment(:table, filter: { url: "/x" }) do |slots|
        slots.filter { '<div class="slot-marker">custom filter</div>'.html_safe }
      end

      form = fragment.css("form").first
      marker = fragment.css(".slot-marker").first

      expect(marker).not_to be_nil
      expect(marker.text).to eq("custom filter")
      expect(marker.ancestors.map(&:name)).to include(form.name)
      expect(marker.ancestors).to include(form)
    end

    it "still renders the form shell, hidden fields, and buttons around the slot content" do
      fragment = component_fragment(
        :table, filter: { url: "/x", hidden: { a: "1" }, reset: "/reset" }
      ) do |slots|
        slots.filter { '<div class="slot-marker">custom filter</div>'.html_safe }
      end

      form = fragment.css("form").first
      expect(form["action"]).to eq("/x")
      expect(fragment.css("input[type=hidden][name=a]").first["value"]).to eq("1")
      expect(fragment.css("a.btn.btn-link").first["href"]).to eq("/reset")
      expect(fragment.css(".slot-marker")).not_to be_empty
    end

    it "raises ArgumentError when both fields: and a filter slot are given" do
      expect {
        component_fragment(:table, filter: { fields: [{ name: "q" }] }) do |slots|
          slots.filter { "x" }
        end
      }.to raise_error { |error|
        expect(error.cause).to be_a(ArgumentError)
        expect(error.cause.message).to match(/filter/i)
      }
    end
  end
end
