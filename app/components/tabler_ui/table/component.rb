# frozen_string_literal: true

module TablerUi
  module Table
    # Table component for Tabler UI. Renders a `.card > .table-responsive >
    # table` wrapper (card optional) around a `<thead>` built from `columns:`
    # and a `<tbody>` built by invoking each column's `:value` callable
    # against every row in `data:`.
    #
    # @example Basic usage
    #   <%= tabler_ui.table columns: [{ label: "Name", value: ->(row) { row[:name] } }],
    #                       data: User.all %>
    #
    # @example Styling modifiers
    #   <%= tabler_ui.table columns: columns, data: rows, striped: true, hover: true %>
    #
    # @example Nested inside an existing card -- opt out of the card wrapper
    #   <%= tabler_ui.table columns: columns, data: rows, card: false %>
    #
    # @example Highlighting rows conditionally via a callable
    #   <%= tabler_ui.table columns: columns, data: rows,
    #                       row_html: ->(row) { row.overdue? ? { class: "table-danger" } : {} } %>
    #
    # @example Rule 5 hooks
    #   <%= tabler_ui.table columns: columns, data: rows,
    #                       html: { class: "mb-4" }, table_html: { class: "table-xl" },
    #                       thead_html: { class: "text-uppercase" },
    #                       tbody_html: { data: { testid: "rows" } },
    #                       row_html: { class: "align-middle" } %>
    class Component
      include TablerUi::Base

      attr_reader :columns, :data

      # @param options [Hash]
      # @option options [Array<Hash>] :columns Each hash carries a `:label`, an
      #   optional `:class` (appended to the cell's own class, never replacing
      #   it), and a `:value` callable invoked as `value.call(row)` per row.
      # @option options [Enumerable] :data The row collection (default: [])
      # @option options [Boolean] :striped table-striped (default: false)
      # @option options [Boolean] :hover   table-hover (default: false)
      # @option options [Boolean] :bordered table-bordered (default: false)
      # @option options [Boolean] :sm      table-sm (default: false)
      # @option options [Boolean] :nowrap  table-nowrap (default: false)
      # @option options [Boolean] :vcenter table-vcenter (default: false)
      # @option options [Boolean] :card    Wrap the table in a `.card` /
      #   `.table-responsive` shell (default: true). Set to false to nest the
      #   table inside an existing card without double-wrapping.
      # @option options [Hash]    :html       Rule 5 HTML hook for the outermost
      #   element -- the `.card` wrapper, or the `.table-responsive` div when
      #   `card: false` (part :root)
      # @option options [Hash]    :table_html Rule 5 HTML hook for the `<table>` (part :table)
      # @option options [Hash]    :thead_html Rule 5 HTML hook for the `<thead>` (part :thead)
      # @option options [Hash]    :tbody_html Rule 5 HTML hook for the `<tbody>` (part :tbody)
      # @option options [Hash, Proc] :row_html Rule 5 HTML hook applied to each
      #   `<tr>` in the body (part :row). Either a plain Hash (applied to every
      #   row) or a callable taking the row object and returning a Hash (so
      #   callers can style rows conditionally, e.g. highlighting overdue
      #   records).
      def initialize(options = {})
        @columns = options[:columns] || []
        @data = options[:data] || []
        @striped = options[:striped]
        @hover = options[:hover]
        @bordered = options[:bordered]
        @sm = options[:sm]
        @nowrap = options[:nowrap]
        @vcenter = options[:vcenter]
        @card = options.fetch(:card, true)
        @row_html = options[:row_html]

        initialize_html_options(options)
      end

      # @return [Boolean] whether the .card wrapper is rendered
      def card?
        !!@card
      end

      # @return [Hash] attributes for the outermost element (part :root):
      #   the .card wrapper, or the .table-responsive div when card: false.
      def root_attributes
        html_for(:root, class: card? ? "card" : "table-responsive")
      end

      # @return [Hash] attributes for the .table-responsive div, only used
      #   when the .card wrapper is also rendered (part :root handles it
      #   directly when card: false).
      def responsive_attributes
        { class: "table-responsive" }
      end

      # @return [Hash] attributes for the <table> (part :table), merged with
      #   whatever the caller supplied via table_html:.
      def table_attributes
        html_for(:table, class: table_classes)
      end

      # @return [Hash] attributes for the <thead> (part :thead), merged with
      #   whatever the caller supplied via thead_html:.
      def thead_attributes
        html_for(:thead)
      end

      # @return [Hash] attributes for the <tbody> (part :tbody), merged with
      #   whatever the caller supplied via tbody_html:.
      def tbody_attributes
        html_for(:tbody)
      end

      # @param row [Object] the current row being rendered
      # @return [Hash] attributes for this row's <tr> (part :row). row_html:
      #   may be a plain Hash (applied to every row) or a callable taking the
      #   row and returning a Hash (applied per row); either way it's merged
      #   over the row defaults using the same merge-not-replace contract as
      #   every other hook. TablerUi::Base#html_for resolves the callable.
      def row_attributes(row)
        html_for(:row, {}, row)
      end

      # @param col [Hash] a column definition from :columns
      # @return [Hash] attributes for a <th>/<td> cell -- the column's own
      #   :class option appended (never replacing) any base class.
      def cell_attributes(col, base_class: nil)
        TablerUi::HtmlOptions.merge_html({ class: base_class }, { class: col[:class] })
      end

      private

      def table_classes
        classes = %w[table card-table]
        classes << "table-striped" if @striped
        classes << "table-hover" if @hover
        classes << "table-bordered" if @bordered
        classes << "table-sm" if @sm
        classes << "table-nowrap" if @nowrap
        classes << "table-vcenter" if @vcenter
        classes.join(" ")
      end
    end
  end
end
