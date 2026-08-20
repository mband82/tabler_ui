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
      it "method: :get (default) with a frame: auto-submits via Stimulus and renders no Apply button" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }] }, frame: "tbl")
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

      it "method: :get, auto: false overrides the default -- Apply button renders, no Stimulus wiring, " \
         "even with a frame: that would otherwise default auto: to true" do
        fragment = component_fragment(:table, filter: { method: :get, auto: false, fields: [{ name: "q" }] },
                                               frame: "tbl")
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

    describe "auto: default depends on frame: (an auto-submitting filter with no frame: is a full page " \
             "navigation on every debounced keystroke -- see the component's :auto docs)" do
      it "method: :get with frame: auto-submits (Stimulus wiring present, no Apply button)" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }] }, frame: "tbl")
        form = fragment.css("form").first

        expect(form["data-controller"]).to eq("tabler-ui--filter")
        expect(fragment.css("button.btn.btn-primary")).to be_empty
      end

      it "method: :get with no frame: does NOT auto-submit (no data-controller, Apply button renders)" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }] })
        form = fragment.css("form").first

        expect(form["data-controller"]).to be_nil
        expect(fragment.css("button.btn.btn-primary")).not_to be_empty
      end

      it "method: :post with frame: still does NOT auto-submit -- a frame: alone is not enough" do
        fragment = component_fragment(:table, filter: { method: :post, fields: [{ name: "q" }] }, frame: "tbl")
        form = fragment.css("form").first

        expect(form["data-controller"]).to be_nil
        expect(fragment.css("button.btn.btn-primary")).not_to be_empty
      end

      it "CAVEAT: explicit auto: true with no frame: still auto-submits -- a deliberate opt-in into a " \
         "form that loses focus/scroll position on every debounced submit (e.g. a host driving the form " \
         "with Turbo Streams or its own JS)" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }], auto: true })
        form = fragment.css("form").first

        expect(form["data-controller"]).to eq("tabler-ui--filter")
        expect(fragment.css("button.btn.btn-primary")).to be_empty
      end

      it "explicit auto: false with a frame: does NOT auto-submit" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }], auto: false }, frame: "tbl")
        form = fragment.css("form").first

        expect(form["data-controller"]).to be_nil
        expect(fragment.css("button.btn.btn-primary")).not_to be_empty
      end

      it "debounce: is only emitted when auto-submit is actually on" do
        auto_fragment = component_fragment(:table, filter: { fields: [{ name: "q" }], debounce: 500 },
                                                     frame: "tbl")
        non_auto_fragment = component_fragment(:table, filter: { fields: [{ name: "q" }], debounce: 500 })

        expect(auto_fragment.css("form").first["data-tabler-ui--filter-debounce-value"]).to eq("500")
        expect(non_auto_fragment.css("form").first.attribute("data-tabler-ui--filter-debounce-value")).to be_nil
      end
    end

    it "debounce: 500 renders as data-tabler-ui--filter-debounce-value on the form, when auto-submitting" do
      fragment = component_fragment(:table, filter: { debounce: 500, fields: [{ name: "q" }] }, frame: "tbl")

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

    describe "button:" do
      it "wraps the input in .input-group with an attached button.btn[type=submit] carrying the label" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q", button: "Go" }] })
        group = fragment.css(".input-group").first

        expect(group).not_to be_nil

        input = group.css("input").first
        button = group.css("button").first

        expect(input).not_to be_nil
        expect(button["type"]).to eq("submit")
        expect(button["class"].to_s.split(/\s+/)).to include("btn")
        expect(button.text).to eq("Go")
      end

      it "without button:, renders no .input-group wrapper at all" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }] })

        expect(fragment.css(".input-group")).to be_empty
      end

      it "raises ArgumentError for button: on a :select field" do
        expect {
          component_fragment(
            :table, filter: { fields: [{ name: "status", type: :select, options: %w[active inactive], button: "Go" }] }
          )
        }.to raise_error(ArgumentError, /button/)
      end

      it "raises ArgumentError for button: on a :date field" do
        expect {
          component_fragment(:table, filter: { fields: [{ name: "from", type: :date, button: "Go" }] })
        }.to raise_error(ArgumentError, /button/)
      end

      it "works alongside auto: true -- the button submits immediately, no separate Apply button renders" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q", button: "Go" }], auto: true })
        form = fragment.css("form").first

        expect(form["data-controller"]).to eq("tabler-ui--filter")
        expect(fragment.css(".input-group button.btn").first.text).to eq("Go")
        expect(fragment.css("button.btn.btn-primary")).to be_empty
      end

      it "works alongside auto: false -- the field button and a separate Apply button both render" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q", button: "Go" }], auto: false })

        expect(fragment.css(".input-group button.btn").first.text).to eq("Go")
        expect(fragment.css("button.btn.btn-primary").first.text).to eq(I18n.t("tabler_ui.table.apply"))
      end

      it_behaves_like "an element with an html hook", :table,
        { filter: { fields: [{ name: "q", button: "Go" }] } },
        hook: :filter_button_html, selector: "button.btn"
    end

    describe "min_chars:" do
      it "INERT: with a frame but auto: false, output is byte-identical to the same call without min_chars:" do
        base = { filter: { fields: [{ name: "q" }], auto: false }, frame: "tbl" }
        with_min_chars = { filter: { fields: [{ name: "q" }], auto: false, min_chars: 3 }, frame: "tbl" }

        expect(render_component(:table, **with_min_chars)).to eq(render_component(:table, **base))
      end

      it "INERT: with auto-submit but no frame:, output is byte-identical to the same call without min_chars:" do
        base = { filter: { fields: [{ name: "q" }], auto: true } }
        with_min_chars = { filter: { fields: [{ name: "q" }], auto: true, min_chars: 3 } }

        expect(render_component(:table, **with_min_chars)).to eq(render_component(:table, **base))
      end

      it "ACTIVE (auto + frame): the form carries data-tabler-ui--filter-min-chars-value" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }], min_chars: 3 }, frame: "tbl")

        expect(fragment.css("form").first["data-tabler-ui--filter-min-chars-value"]).to eq("3")
      end

      it "ACTIVE: the search input carries data-tabler-ui--filter-target=\"input\"" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }], min_chars: 3 }, frame: "tbl")

        expect(fragment.css("input.form-control").first["data-tabler-ui--filter-target"]).to eq("input")
      end

      it "ACTIVE: renders the translated hint as the input's next sibling for a plain field" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }], min_chars: 3 }, frame: "tbl")
        hint = fragment.css("input.form-control + div.invalid-feedback").first

        expect(hint).not_to be_nil
        expect(hint.text).to eq("Enter at least 3 characters to search.")
        expect(hint["data-tabler-ui--filter-target"]).to eq("hint")
      end

      it "ACTIVE + button:: the hint is the .input-group's last child, after the button" do
        fragment = component_fragment(
          :table, filter: { fields: [{ name: "q", button: "Go" }], min_chars: 3 }, frame: "tbl"
        )

        expect(fragment.css(".input-group > input + button + div.invalid-feedback")).not_to be_empty
      end

      it "min_chars_hint: overrides the hint text" do
        fragment = component_fragment(
          :table, filter: { fields: [{ name: "q" }], min_chars: 3, min_chars_hint: "Type more, please" },
                  frame: "tbl"
        )

        expect(fragment.css("div.invalid-feedback").first.text).to eq("Type more, please")
      end

      it "raises ArgumentError for min_chars: 0" do
        expect {
          component_fragment(:table, filter: { fields: [{ name: "q" }], min_chars: 0 })
        }.to raise_error(ArgumentError, /min_chars/)
      end

      it "raises ArgumentError for a negative min_chars:" do
        expect {
          component_fragment(:table, filter: { fields: [{ name: "q" }], min_chars: -1 })
        }.to raise_error(ArgumentError, /min_chars/)
      end

      it "raises ArgumentError for a non-Integer min_chars:" do
        expect {
          component_fragment(:table, filter: { fields: [{ name: "q" }], min_chars: "3" })
        }.to raise_error(ArgumentError, /min_chars/)
      end

      it "raises ArgumentError when fields: has no :search/:text field for min_chars: to attach to" do
        expect {
          component_fragment(
            :table, filter: { fields: [{ name: "status", type: :select, options: %w[active inactive] }], min_chars: 3 }
          )
        }.to raise_error(ArgumentError, /search|text/)
      end

      it_behaves_like "an element with an html hook", :table,
        { filter: { fields: [{ name: "q" }], min_chars: 3 }, frame: "tbl" },
        hook: :filter_hint_html, selector: "div.invalid-feedback"

      it "REGRESSION: min_chars:, frame: and an auto-submitting filter: together keep the Stimulus " \
         "data-controller/data-action, data-turbo-frame, AND the min-chars value all on the form " \
         "(extends the frame:/filter: composition regression above)" do
        fragment = component_fragment(:table, filter: { fields: [{ name: "q" }], min_chars: 3 }, frame: "tbl")
        form = fragment.css("form").first

        expect(form["data-controller"]).to eq("tabler-ui--filter")
        expect(form["data-action"]).to include("input->tabler-ui--filter#submit")
        expect(form["data-action"]).to include("change->tabler-ui--filter#submit")
        expect(form["data-turbo-frame"]).to eq("tbl")
        expect(form["data-tabler-ui--filter-min-chars-value"]).to eq("3")
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

  describe "footer slot:" do
    it "renders a .card-footer div containing the block's content" do
      fragment = component_fragment(:table) do |slots|
        slots.footer { '<div class="slot-marker">Page 1 of 3</div>'.html_safe }
      end

      footer = fragment.css(".card-footer").first
      marker = fragment.css(".slot-marker").first

      expect(footer).not_to be_nil
      expect(marker).not_to be_nil
      expect(marker.text).to eq("Page 1 of 3")
      expect(marker.ancestors).to include(footer)
    end

    it "card: false renders the footer as .mt-3 instead of .card-footer" do
      fragment = component_fragment(:table, card: false) do |slots|
        slots.footer { "Page 1 of 3" }
      end

      expect(fragment.css(".card-footer")).to be_empty
      footer = fragment.css(".mt-3").first
      expect(footer).not_to be_nil
      expect(footer.text).to eq("Page 1 of 3")
    end

    it "no footer slot renders no footer div at all, and the rest of the output is unchanged" do
      without_block = render_component(:table)
      with_unused_block = render_component(:table) { |slots| }

      expect(with_unused_block).to eq(without_block)

      fragment = component_fragment(:table)
      expect(fragment.css(".card-footer")).to be_empty
      expect(fragment.css(".mt-3")).to be_empty
    end

    it "DESIGN: with frame: and a footer, .table-responsive and the footer both render inside the " \
       "<turbo-frame>, table-responsive first -- a footer/pager rendered outside the frame would go " \
       "stale (e.g. keep showing 'page 1' as current) after the frame navigates" do
      fragment = component_fragment(:table, frame: "tbl") do |slots|
        slots.footer { "Page 1 of 3" }
      end

      frame = fragment.css("turbo-frame").first
      element_children = frame.children.select(&:element?)

      expect(element_children.map { |el| el["class"] }).to eq(%w[table-responsive card-footer])
    end

    it "CONTRAST: with frame:, the filter toolbar is NOT inside the <turbo-frame> -- unlike the footer " \
       "above, the search input must not be re-rendered out from under the user while they are typing" do
      fragment = component_fragment(:table, filter: { fields: [{ name: "q" }] }, frame: "tbl")

      frame = fragment.css("turbo-frame").first
      expect(frame.css("form")).to be_empty
      expect(fragment.css("form")).not_to be_empty
    end

    # The shared example's `hook_fragment` never passes a block, but the
    # footer only renders via `slots.footer { ... }` -- there is no
    # `footer:` options hash to trigger it any other way (see the class
    # docs). Hand-written instead, mirroring the thead_html/tbody_html/
    # frame_html specs elsewhere in this file for the same reason.
    describe "footer_html: hook" do
      it "keeps the component's own class on the .card-footer element" do
        fragment = component_fragment(:table) { |slots| slots.footer { "content" } }

        expect(fragment.css(".card-footer")).not_to be_empty
      end

      it "appends a caller-supplied class instead of replacing the component's own" do
        fragment = component_fragment(:table, footer_html: { class: "hook-extra-class" }) do |slots|
          slots.footer { "content" }
        end
        element = fragment.css(".card-footer").first

        expect(element).not_to be_nil
        classes = element["class"].to_s.split(/\s+/)
        expect(classes).to include("hook-extra-class")
        expect(classes.size).to be > 1
      end

      it "passes through a caller-supplied id" do
        fragment = component_fragment(:table, footer_html: { id: "hook-test-id" }) do |slots|
          slots.footer { "content" }
        end

        expect(fragment.css(".card-footer").first["id"]).to eq("hook-test-id")
      end

      it "passes through caller-supplied data attributes" do
        fragment = component_fragment(:table, footer_html: { data: { testid: "hook-test-data" } }) do |slots|
          slots.footer { "content" }
        end

        expect(fragment.css(".card-footer").first["data-testid"]).to eq("hook-test-data")
      end
    end
  end

  describe "frame:" do
    it "DEGRADATION: with no frame:, renders no turbo-frame element and no turbo attribute anywhere" do
      columns = [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }]
      fragment = component_fragment(
        :table, columns: columns,
                sort_url: ->(key, dir) { "/x?sort=#{key}&dir=#{dir}" },
                filter: { reset: "/reset", fields: [{ name: "q" }] }
      )

      expect(fragment.css("turbo-frame")).to be_empty
      expect(fragment.to_html).not_to match(/turbo/i)
    end

    it "String shorthand and the equivalent Hash form produce identical markup" do
      string_form = component_fragment(:table, frame: "tbl")
      hash_form = component_fragment(:table, frame: { id: "tbl" })

      expect(string_form.to_html).to eq(hash_form.to_html)
    end

    it "wraps .table-responsive in a <turbo-frame>, with card: true" do
      fragment = component_fragment(:table, frame: "tbl")

      expect(fragment.css("turbo-frame > div.table-responsive")).not_to be_empty
    end

    it "wraps .table-responsive in a <turbo-frame>, with card: false" do
      fragment = component_fragment(:table, frame: "tbl", card: false)

      expect(fragment.css("turbo-frame > div.table-responsive")).not_to be_empty
    end

    it "advance: defaults to true, emitting data-turbo-action=advance on the frame" do
      fragment = component_fragment(:table, frame: "tbl")

      expect(fragment.css("turbo-frame").first["data-turbo-action"]).to eq("advance")
    end

    it "advance: false omits data-turbo-action entirely" do
      fragment = component_fragment(:table, frame: { id: "tbl", advance: false })

      expect(fragment.css("turbo-frame").first.attribute("data-turbo-action")).to be_nil
    end

    it "src: and loading: pass through as attributes on the frame" do
      fragment = component_fragment(:table, frame: { id: "tbl", src: "/x", loading: :lazy })
      frame_el = fragment.css("turbo-frame").first

      expect(frame_el["src"]).to eq("/x")
      expect(frame_el["loading"]).to eq("lazy")
    end

    it "raises ArgumentError for an unknown frame: { loading: }" do
      expect {
        component_fragment(:table, frame: { id: "tbl", loading: :bogus })
      }.to raise_error(ArgumentError, /loading/)
    end

    it "raises ArgumentError for a blank frame: { id: }" do
      expect {
        component_fragment(:table, frame: { id: "" })
      }.to raise_error(ArgumentError, /id/)
    end

    it "REGRESSION: filter: (auto-submitting :get) and frame: together keep the Stimulus " \
       "data-controller/data-action AND data-turbo-frame all on the form" do
      fragment = component_fragment(:table, filter: { fields: [{ name: "q" }] }, frame: "tbl")
      form = fragment.css("form").first

      expect(form["data-controller"]).to eq("tabler-ui--filter")
      expect(form["data-action"]).to include("input->tabler-ui--filter#submit")
      expect(form["data-action"]).to include("change->tabler-ui--filter#submit")
      expect(form["data-turbo-frame"]).to eq("tbl")
    end

    it "the Reset link carries data-turbo-frame, but the sortable header link does not" do
      columns = [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }]
      fragment = component_fragment(
        :table, columns: columns,
                sort_url: ->(key, dir) { "/x?sort=#{key}&dir=#{dir}" },
                filter: { reset: "/reset", fields: [{ name: "q" }] }, frame: "tbl"
      )

      reset_link = fragment.css("a.btn.btn-link").first
      sort_link = fragment.css("a.table-sort").first

      expect(reset_link["data-turbo-frame"]).to eq("tbl")
      expect(sort_link.attribute("data-turbo-frame")).to be_nil
    end

    # turbo-frame carries no base class of its own (frame_attributes only
    # ever sets id/src/loading/data-turbo-action), so the shared example's
    # "component class survives alongside the caller's" check (which asserts
    # more than one class ends up on the element) doesn't fit -- hand-written
    # instead, mirroring the thead_html/tbody_html specs above.
    it "passes id/data/class through frame_html: onto the <turbo-frame>" do
      fragment = component_fragment(:table, frame: "tbl",
                                             frame_html: { class: "hook-extra-class", id: "hook-test-id",
                                                            data: { testid: "hook-test-data" } })
      element = fragment.css("turbo-frame").first

      expect(element).not_to be_nil
      expect(element["class"].to_s.split(/\s+/)).to include("hook-extra-class")
      expect(element["id"]).to eq("hook-test-id")
      expect(element["data-testid"]).to eq("hook-test-data")
    end

    it_behaves_like "an element with an html hook", :table,
      { filter: { reset: "/reset", fields: [{ name: "q" }] } },
      hook: :filter_reset_html, selector: "a.btn-link"
  end
end
