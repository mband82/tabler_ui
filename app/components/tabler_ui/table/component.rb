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
      # @option options [Boolean, String] :responsive Controls the horizontal-
      #   scroll wrapper. `true` (default) emits plain `table-responsive`
      #   (scrolls at every width). A breakpoint string ("sm"/"md"/"lg"/"xl"/
      #   "xxl") emits `table-responsive-<bp>` instead (scrolls only below
      #   that breakpoint). `false` emits neither class -- see
      #   #responsive_class for what that means when `card: false`.
      # @option options [Boolean, String] :mobile Stacks the table into a
      #   card-like list below a breakpoint via `table-mobile` (`true`, all
      #   widths) or `table-mobile-<bp>` (a breakpoint string) on the
      #   `<table>` element. When set, every `<td>` also gets a `data-label`
      #   attribute (its column's `:label`), which the CSS reads to draw the
      #   heading in the stacked layout.
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
        @responsive = normalize_breakpoint_flag(options.fetch(:responsive, true), context: "table responsive")
        @mobile = normalize_breakpoint_flag(options[:mobile], context: "table mobile")
        @row_html = options[:row_html]

        initialize_html_options(options)
      end

      # @return [Boolean] whether the .card wrapper is rendered
      def card?
        !!@card
      end

      # @return [Boolean] whether mobile: is set (in either its `true` or
      #   breakpoint-string form) -- i.e. whether cells need a data-label.
      def mobile?
        !!@mobile
      end

      # @return [String, nil] the responsive-wrapper class for the current
      #   responsive: setting, or nil when responsive: false. `true` (the
      #   default) scrolls at every width; a breakpoint string scrolls only
      #   below that breakpoint.
      def responsive_class
        case @responsive
        when true then "table-responsive"
        when false, nil then nil
        else "table-responsive-#{@responsive}"
        end
      end

      # @return [String, nil] the table-mobile class for the current mobile:
      #   setting, or nil when mobile: is not set.
      def mobile_class
        case @mobile
        when true then "table-mobile"
        when false, nil then nil
        else "table-mobile-#{@mobile}"
        end
      end

      # @return [Hash] attributes for the outermost element (part :root): the
      #   .card wrapper (unaffected by responsive:, since the responsive class
      #   lives on the nested .table-responsive div in that layout), or the
      #   responsive-wrapper div itself when card: false -- in which case
      #   responsive: false means the root element carries no class at all,
      #   rather than removing the wrapper (removing it would leave the
      #   :root hook with no element to attach to).
      def root_attributes
        html_for(:root, card? ? { class: "card" } : responsive_defaults)
      end

      # @return [Hash] attributes for the .table-responsive(-<bp>) div, only
      #   used when the .card wrapper is also rendered (part :root handles it
      #   directly when card: false). Empty (no class) when responsive: false.
      def responsive_attributes
        responsive_defaults
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
      # @return [Hash] attributes for a <th> cell -- the column's own :class
      #   option appended (never replacing) any base class.
      def cell_attributes(col, base_class: nil)
        TablerUi::HtmlOptions.merge_html({ class: base_class }, { class: col[:class] })
      end

      # @param col [Hash] a column definition from :columns
      # @return [Hash] attributes for a <td> cell -- #cell_attributes plus,
      #   when mobile: is set, a data-label carrying the column's :label so
      #   the stacked mobile layout's CSS can draw the heading (it reads
      #   `td[data-label]:before { content: attr(data-label) }`; the <thead>
      #   is hidden in that layout). Omitted when the column's label is
      #   blank/nil -- an empty heading is worse than no heading, and this
      #   also lets a column opt out of the mobile heading entirely (e.g. an
      #   actions column of icon-only buttons).
      def data_cell_attributes(col, base_class: nil)
        attrs = cell_attributes(col, base_class: base_class)
        return attrs unless mobile? && col[:label].present?

        attrs.merge(data: { label: col[:label] })
      end

      private

      # Normalizes a `responsive:`/`mobile:`-style option: `true`/`false`/nil
      # pass through unchanged, anything else is validated as a breakpoint
      # string via TablerUi::Breakpoint.validate! (raising ArgumentError for
      # an unrecognised value).
      def normalize_breakpoint_flag(value, context:)
        return value if value == true || value == false || value.nil?

        TablerUi::Breakpoint.validate!(value, context: context)
      end

      # @return [Hash] `{ class: responsive_class }`, or `{}` when
      #   responsive_class is nil -- keeping :class out of the hash (rather
      #   than passing class: nil through) avoids an empty class="" attribute
      #   on the rendered element.
      def responsive_defaults
        responsive_class ? { class: responsive_class } : {}
      end

      def table_classes
        classes = %w[table card-table]
        classes << "table-striped" if @striped
        classes << "table-hover" if @hover
        classes << "table-bordered" if @bordered
        classes << "table-sm" if @sm
        classes << "table-nowrap" if @nowrap
        classes << "table-vcenter" if @vcenter
        classes << mobile_class if mobile_class
        classes.join(" ")
      end
    end
  end
end
