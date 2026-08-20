# frozen_string_literal: true

module TablerUi
  module Table
    # Table component for Tabler UI. Renders a `.card > .table-responsive >
    # table` wrapper (card optional) around a `<thead>` built from `columns:`
    # and a `<tbody>` built by invoking each column's `:value` callable
    # against every row in `data:`.
    #
    # Also wires up two adjacent pieces of table chrome -- sortable column
    # headers and a filter/search toolbar -- without ever touching an ORM,
    # `params`, or a query. Exactly like `pagination` (see its class docs),
    # this component's entire input for those pieces is the caller's current
    # state (which column/direction is sorted, what the filter fields'
    # current values are) plus a way to build a URL. Kaminari, Ransack,
    # hand-rolled `params.permit`, whatever the host app uses upstream is
    # none of this component's business -- it only renders links and a form.
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
    #
    # @example Sortable columns
    #   <%= tabler_ui.table columns: [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }],
    #                       data: rows,
    #                       sort: { key: params[:sort], dir: params[:dir] },
    #                       sort_url: ->(key, dir) { users_path(sort: key, dir: dir) } %>
    #
    # @example Declarative filter toolbar (auto-submitting GET)
    #   <%= tabler_ui.table columns: columns, data: rows,
    #                       filter: {
    #                         url: users_path,
    #                         hidden: { sort: params[:sort], dir: params[:dir] },
    #                         fields: [
    #                           { name: "q", value: params[:q] },
    #                           { name: "status", type: :select, label: "Status",
    #                             value: params[:status], include_blank: true,
    #                             options: %w[active inactive] }
    #                         ]
    #                       } %>
    #
    # @example Filter slot -- arbitrary form contents in place of fields:
    #   <%= tabler_ui.table columns: columns, data: rows, filter: { url: users_path } do |slots| %>
    #     <% slots.filter do %>
    #       <%= tag.input(type: "search", name: "q", value: params[:q], class: "form-control") %>
    #     <% end %>
    #   <% end %>
    #
    # @example Turbo Frame -- String shorthand, sorting/filtering stay in-frame
    #   <%= tabler_ui.table columns: columns, data: rows,
    #                       sort: { key: params[:sort], dir: params[:dir] },
    #                       sort_url: ->(key, dir) { users_path(sort: key, dir: dir) },
    #                       frame: "users-table" %>
    #
    # @example Turbo Frame -- Hash form, lazily loaded, no history entries
    #   <%= tabler_ui.table columns: columns, data: [],
    #                       frame: { id: "users-table", src: users_path, loading: :lazy, advance: false } %>
    #
    # @example Footer slot -- a pager that swaps with the table instead of going stale
    #   <%= tabler_ui.table columns: columns, data: rows, frame: "users-table" do |slots| %>
    #     <% slots.footer do %>
    #       <%= tabler_ui.pagination current: @pagy.page, total: @pagy.pages,
    #                                url: ->(n) { users_path(page: n) } %>
    #     <% end %>
    #   <% end %>
    class Component
      include TablerUi::Base

      # Valid values for a filter field's `type:`.
      FILTER_FIELD_TYPES = %i[search text select date].freeze

      # Filter field types whose column wrapper grows to fill space
      # (`col-12 col-md`) rather than sizing to content (`col-12 col-md-auto`).
      GROWING_FILTER_FIELD_TYPES = %i[search text].freeze

      # Valid values for `filter: { method: }`.
      FILTER_METHODS = %i[get post].freeze

      # Valid values for `sort: { dir: }`.
      SORT_DIRS = %i[asc desc].freeze

      # Valid values for `frame: { loading: }`.
      FRAME_LOADING_VALUES = %i[lazy eager].freeze

      attr_reader :columns, :data

      # @param options [Hash]
      # @option options [Array<Hash>] :columns Each hash carries a `:label`, an
      #   optional `:class` (appended to the cell's own class, never replacing
      #   it), an optional `:sort` sort key (see "Sorting" below), and a
      #   `:value` callable invoked as `value.call(row)` per row.
      # @option options [Enumerable] :data The row collection (default: [])
      # @option options [Boolean] :striped table-striped (default: false)
      # @option options [Boolean] :hover   table-hover (default: false)
      # @option options [Boolean] :bordered table-bordered (default: false)
      # @option options [Boolean] :sm      table-sm (default: false)
      # @option options [Boolean] :nowrap  table-nowrap (default: false)
      # @option options [Boolean] :vcenter table-vcenter (default: false)
      # @option options [Boolean] :card    Wrap the table in a `.card` /
      #   `.table-responsive` shell (default: true). Set to false to nest the
      #   table inside an existing card without double-wrapping. Also
      #   controls the filter toolbar's own shell -- see "Filtering" below.
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
      # @option options [Hash] :sort Current sort state, `{ key:, dir: }`.
      #   `dir:` accepts :asc/:desc (or their string forms) and defaults to
      #   :asc when `key:` is given without it; an unrecognised `dir:` raises
      #   ArgumentError. nil/absent (the default) means unsorted. See
      #   "Sorting" below.
      # @option options [#call] :sort_url Sorting only -- a callable invoked
      #   as `sort_url.call(key, dir)` returning the href for a sortable
      #   column's header link. Mandatory (raises ArgumentError at
      #   initialize time) as soon as any column carries `sort:`.
      # @option options [Boolean] :sort_reset When true, clicking a column
      #   that is currently sorted :desc cycles to unsorted (`sort_url.call(key,
      #   nil)`) instead of back to :asc (default: false). See "Sorting" below.
      # @option options [Hash] :filter Turns on the filter/search toolbar --
      #   see "Filtering" below. Absent (the default) renders nothing extra
      #   at all; the rest of the table's output is unaffected.
      # @option options [String, Hash] :frame Opt-in Turbo Frame support --
      #   see "Turbo Frames" below. A String is shorthand for `{ id: the
      #   String }`. Absent (the default) renders no `<turbo-frame>` at all;
      #   the rest of the table's output is unaffected.
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
      # @option options [Hash, Proc] :sort_html Rule 5 HTML hook applied to a
      #   sortable column's `<a class="table-sort">` (part :sort). Either a
      #   plain Hash (applied to every sortable header) or a callable taking
      #   the column hash and returning a Hash, following `row_html:`'s
      #   pattern, so callers can vary it per column.
      # @option options [Hash] :filter_html Rule 5 HTML hook for the filter
      #   toolbar's outer element (part :filter), only rendered when
      #   `filter:` is given.
      # @option options [Hash] :filter_form_html Rule 5 HTML hook for the
      #   filter toolbar's `<form>` (part :filter_form).
      # @option options [Hash] :filter_reset_html Rule 5 HTML hook for the
      #   filter toolbar's Reset link (part :filter_reset), only rendered
      #   when `filter: { reset: }` is given.
      # @option options [Hash] :filter_button_html Rule 5 HTML hook for a
      #   filter field's attached search button (part :filter_button), only
      #   rendered for a field carrying `button:` -- see "Filtering" below.
      # @option options [Hash] :filter_hint_html Rule 5 HTML hook for the
      #   `min_chars:` hint element (part :filter_hint), only rendered when
      #   `filter: { min_chars: }` is given -- see "Filtering" below.
      # @option options [Hash] :frame_html Rule 5 HTML hook for the
      #   `<turbo-frame>` element (part :frame), only rendered when `frame:`
      #   is given.
      # @option options [Hash] :footer_html Rule 5 HTML hook for the footer
      #   slot's wrapper (part :footer), only rendered when the caller sets
      #   `slots.footer { ... }` -- see "Footer" below. There is no `footer:`
      #   options hash to go with it (unlike `filter:`) -- the footer is a
      #   slot only, on/off purely by whether the block set it.
      #
      # ## Sorting
      #
      # A column becomes sortable by giving it a `:sort` key (any sort key
      # value -- typically the column/attribute name the caller's query
      # understands). Its `<th>` then renders as
      # `<a class="table-sort">Label</a>` instead of plain text, linking to
      # `sort_url.call(key, dir)` where `dir` is whichever direction that
      # click *would* apply next:
      #
      # * not currently sorted on this column -> :asc
      # * currently sorted :asc on this column -> :desc
      # * currently sorted :desc on this column -> :asc, or with
      #   `sort_reset: true` -> nil (`sort_url.call(key, nil)`, so the caller
      #   can build a link back to the unsorted state)
      #
      # The currently sorted column's `<th>` carries `aria-sort="ascending"`
      # or `"descending"`, and its `<a>` carries a matching `asc`/`desc`
      # class (read by the `.table-sort` CSS to draw the direction arrow).
      # Every other sortable header is plain `class="table-sort"`, and
      # non-sortable columns are untouched -- exactly the plain `<th>` this
      # component always rendered.
      #
      # ## Filtering
      #
      # `filter:` is a nested options hash that turns on a search/filter
      # toolbar rendered above the table (inside the `.card` when `card:
      # true`, as a sibling before it otherwise). It has two ways in:
      #
      # 1. **Declarative** -- `fields:`, an array of field hashes (`:name`,
      #    `:type`, `:label`, `:placeholder`, `:value`, `:options`,
      #    `:include_blank`, `:col`, `:html`, `:id`). The component renders
      #    the inputs.
      # 2. **Slot** -- a block that sets `slots.filter { ... }`, supplying
      #    the form's contents directly. `fields:` and a filter slot are
      #    mutually exclusive (raises ArgumentError, mirroring pagination's
      #    computed-vs-builder guard) -- see #guard_filter_slot!.
      #
      # Either way the surrounding form shell, hidden fields, and buttons
      # are still built by the component:
      #
      # * `:url` -- form `action` (optional; omitted entirely when absent).
      # * `:method` -- :get (default) or :post; anything else raises
      #   ArgumentError. This never fakes Rails' CSRF token or a `_method`
      #   override field -- it is plain HTML `method="get"`/`"post"`. A
      #   caller needing CSRF protection on :post supplies it themselves via
      #   `hidden:`.
      # * `:auto` -- whether the form self-submits on input/change, via the
      #   `tabler-ui--filter` Stimulus controller (already shipped and
      #   registered by this gem -- see
      #   app/javascript/controllers/tabler_ui/filter_controller.js).
      #   Defaults to true only when the form is :get AND the table has a
      #   `frame:` -- the one combination where an auto-submit lands
      #   somewhere sensible, a Turbo Frame swap rather than a full page
      #   navigation. Every other combination (a :post form; a :get form
      #   with no `frame:`) defaults to false. An explicit value always wins
      #   in either direction. When true, an Apply button is not rendered.
      #
      #   An explicit `auto: true` on a table with no `frame:` is not
      #   forbidden -- a host driving the response with Turbo Streams or its
      #   own JavaScript may have good reason to. But left at that setting
      #   without such a setup (or with the pre-fix default this replaces),
      #   every keystroke's debounced submit is a full navigation -- a Turbo
      #   Drive visit, or a plain page reload with no Turbo at all -- so the
      #   body gets replaced, the search input loses focus, and the page
      #   scrolls back to the top mid-typing.
      # * `:hidden` -- `name => value` pairs rendered as hidden inputs (e.g.
      #   to preserve the current sort state across a GET filter submit).
      #   Entries whose value is nil/blank are skipped.
      # * `:reset` -- a URL; when present, renders a "Reset" link.
      # * `:submit` -- Apply button label (default: a translated "Apply"),
      #   only rendered when `auto:` is false.
      # * `:debounce` -- milliseconds, forwarded to the Stimulus controller.
      # * `:min_chars` -- a positive Integer (anything else raises
      #   ArgumentError). Applies to the FIRST `:search`/`:text` field in
      #   `fields:` -- absent such a field, ArgumentError ("needs a search or
      #   text field to apply to"). These two checks are the only ones that
      #   raise -- `min_chars:` is otherwise always *accepted*.
      #
      #   Whether it actually does anything is a separate, silent question
      #   (see #filter_min_chars_active?): it only takes effect when the
      #   form BOTH auto-submits (`auto:` resolves to true) AND the table
      #   has a `frame:` -- exactly the combination `auto:` now defaults to
      #   true under (see `:auto` above), so in the common case (a GET
      #   filter on a framed table, `auto:` left at its default) this
      #   condition is already satisfied without saying anything explicitly.
      #   Missing either, `min_chars:` is a no-op -- the
      #   rendered output is byte-identical to the same call without it: no
      #   `data-tabler-ui--filter-min-chars-value` on the form, no
      #   `data-tabler-ui--filter-target="input"` on the field, no hint
      #   element at all. This is deliberate, not a bug to "fix": without a
      #   frame, a below-threshold submit is a full page reload, and the
      #   server echoes back the blanked search value -- wiping the user's
      #   typed text out of the input. The feature only behaves well when
      #   the form's response swaps in over Turbo instead of replacing the
      #   whole page, so outside that setup it does nothing rather than
      #   half-working.
      #
      #   When active, the tabler-ui--filter Stimulus controller still
      #   submits the form below the threshold (so the URL/query params
      #   stay in sync) but blanks the field's own value first, so the
      #   table falls back to unfiltered results instead of filtering on a
      #   too-short fragment; the hint text appears and the field is marked
      #   `is-invalid` while below the threshold. Clearing the field
      #   entirely (0 characters) always submits normally -- a user can
      #   never get stuck in a filtered state with no way back out. See
      #   app/javascript/controllers/tabler_ui/filter_controller.js for the
      #   submit-time logic; this component only emits the
      #   `data-tabler-ui--filter-min-chars-value` and
      #   `data-tabler-ui--filter-target="input"`/`"hint"` markup it reads.
      # * `:min_chars_hint` -- overrides the hint text shown below the
      #   `min_chars:` field (default: a translated "Enter at least %{count}
      #   characters to search.").
      #
      # Field hashes: `:name` is mandatory (raises ArgumentError when
      # missing/blank). `:type` is one of :search (default), :text, :select,
      # :date (anything else raises ArgumentError) -- :search/:text/:date
      # render `<input type="...">`, :select renders `<select>`. `:value` is
      # always supplied by the caller (this component never remembers
      # state). `:options` (select only) accepts `[label, value]` pairs or
      # plain strings (label == value); `:include_blank` adds an empty
      # option (`true` for a blank label, a String for a labelled one).
      # `:col` overrides the field's column-wrapper class outright (not
      # merged). `:html` merges onto the input/select itself, same
      # merge-not-replace contract as every rule 5 hook. `:id` overrides the
      # field's `id=` attribute outright (not merged). Generated ids are
      # deterministic -- derived from the field's `:name` -- so rendered
      # output stays cache-stable across identical requests; pass `:id`
      # explicitly when the same field `name:` appears in more than one
      # filtered table on the same page, to avoid duplicate DOM ids.
      # `:button` -- a String label (search/text fields only; ArgumentError
      # on :select/:date, since there is nothing sensible for the button to
      # attach to). Wraps the input in a Bootstrap input group with a
      # `type="submit"` button glued to its trailing edge -- works whether
      # or not the form auto-submits; with `auto: true` it simply submits
      # immediately rather than waiting for the debounce.
      #
      # ## Footer
      #
      # `slots.footer { ... }` renders a `.card-footer` (or `mt-3` when
      # `card: false`, which has no card shell for it to sit inside -- the
      # same card:-aware switch the filter toolbar uses, see
      # #filter_wrapper_class/#footer_wrapper_class) after the table, holding
      # whatever the block gives it -- typically a pager
      # (`tabler_ui.pagination`), a row count, a "Showing 1-10 of 50"
      # summary. There is no `footer:` options hash to turn it on the way
      # `filter:` has one -- the footer is a slot only, on/off purely by
      # whether the block set it. Leave it unset and the table's output is
      # byte-identical to before this slot existed.
      #
      # Unlike the filter toolbar, the footer slot renders *inside* `frame:`
      # when one is given -- see "Turbo Frames" below for why the two differ.
      #
      # ## Turbo Frames
      #
      # `frame:` wraps the `.table-responsive` div (the `<table>` and its
      # scroll wrapper) AND the footer slot, when one is given, together in a
      # single `<turbo-frame>`, so sorting, filtering and a footer pager all
      # navigate inside that frame instead of reloading the whole page. This
      # gem takes no turbo-rails dependency -- the `<turbo-frame>` tag is
      # plain markup, inert without Turbo's JS loaded in the host app, and
      # nothing else in this component ever checks whether `frame:` was
      # given except to decide what to render.
      #
      # * `:id` -- the frame's HTML id. Mandatory; a blank/missing value
      #   raises ArgumentError, since there would be nothing for the filter
      #   form/Reset link to target.
      # * `:advance` -- when true (the default), the frame carries
      #   `data-turbo-action="advance"`, so a sort/filter navigation updates
      #   the URL bar and the back button works. false omits the attribute
      #   entirely (Turbo's own default -- a frame navigation, but no
      #   history entry).
      # * `:src` -- optional; emitted as the frame's `src` attribute.
      # * `:loading` -- optional, `:lazy` or `:eager` (string forms
      #   accepted too; anything else raises ArgumentError). Combined with
      #   `src:`, gives a lazily-loaded table -- the frame ships empty and
      #   Turbo fetches `src:` once it scrolls into view.
      #
      # ### Footer in, filter out -- and why they differ
      #
      # The footer slot and the filter toolbar sit on opposite sides of the
      # frame boundary, and both placements are deliberate -- getting either
      # one backwards breaks something, just in opposite ways:
      #
      # * The **footer goes INSIDE the frame.** Anything in it reflects
      #   table state -- a pager, a row count, a "showing 1-10 of 50"
      #   summary -- and has to swap along with the rows or it goes stale. A
      #   pager rendered outside the frame would not re-render when the
      #   frame navigates: clicking page 2 would swap the rows but leave "1"
      #   highlighted in the pager, because the pager markup was never part
      #   of the response that replaced the frame. Practical consequence:
      #   pagination placed in the footer no longer needs its own `frame:`
      #   option -- a link inside a `<turbo-frame>` navigates that frame
      #   automatically without being told to. Passing `frame:` to it anyway
      #   is harmless (Turbo already scopes the navigation correctly) but
      #   redundant.
      # * The **filter toolbar stays OUTSIDE the frame.** The filter form
      #   auto-submits on a debounce (see "Filtering" above); if the frame
      #   wrapped the toolbar, a replacement response landing mid-typing
      #   would replace the search input itself and destroy its focus and
      #   caret position. So instead the filter form and Reset link stay
      #   outside the frame and target it explicitly via
      #   `data-turbo-frame="<id>"` (see #filter_form_attributes and
      #   #filter_reset_attributes). Sortable column headers need no such
      #   attribute -- their `<a>` links already live *inside* the frame, so
      #   Turbo intercepts and scopes the navigation to it automatically; do
      #   not add a redundant `data-turbo-frame` to #sort_attributes.
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

        @sort = normalize_sort(options[:sort])
        @sort_url = options[:sort_url]
        @sort_reset = options.fetch(:sort_reset, false)
        guard_sort_url!

        # frame: is built first -- build_filter's auto: default (see below)
        # needs to know whether a frame: was given, via #frame?.
        @frame = build_frame(options[:frame])
        @filter = build_filter(options[:filter])

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

      # --- Sorting -------------------------------------------------------

      # @param col [Hash] a column definition from :columns
      # @return [Boolean] whether this column's :sort value is present -- the
      #   only thing that makes a column sortable. A column carrying
      #   `sort: nil` is not sortable; the key alone is not enough.
      def sortable?(col)
        col[:sort].present?
      end

      # @param col [Hash] a column definition from :columns
      # @return [Boolean] whether this is the currently sorted column, per
      #   the sort: option. Compared as strings so a caller's `params[:sort]`
      #   (always a String) matches a Symbol :sort key on the column.
      def sorted?(col)
        return false unless @sort && sortable?(col)

        col[:sort].to_s == @sort[:key].to_s
      end

      # @param col [Hash] a column definition from :columns
      # @return [Hash] attributes for a sortable column's <th> (its own
      #   #cell_attributes, plus aria-sort when this is the currently sorted
      #   column). The column's :class lands here, never on the <a> --
      #   see #sort_attributes.
      def header_cell_attributes(col)
        attrs = cell_attributes(col)
        return attrs unless sorted?(col)

        TablerUi::HtmlOptions.merge_html(attrs, aria: { sort: @sort[:dir] == :asc ? "ascending" : "descending" })
      end

      # @param col [Hash] a column definition from :columns
      # @return [Hash] attributes for a sortable column's `<a class=
      #   "table-sort">` (part :sort) -- class reflecting the *current*
      #   state (plain, "asc", or "desc") and href built from #next_sort_dir,
      #   merged with whatever the caller supplied via sort_html: (a plain
      #   Hash or a callable taking the column, following row_html:'s
      #   pattern).
      def sort_attributes(col)
        html_for(:sort, { class: sort_link_classes(col), href: sort_url_for(col) }, col)
      end

      # --- Filtering -------------------------------------------------------

      # @return [Boolean] whether filter: was given at all
      def filter?
        !@filter.nil?
      end

      # @return [Boolean] whether filter: { min_chars: } actually takes
      #   effect on this render. min_chars: is accepted and validated at
      #   construction time regardless (see #validate_min_chars!), but only
      #   changes the rendered output when the form both auto-submits AND
      #   the table has a frame: -- otherwise it is a silent no-op (no
      #   Stimulus value on the form, no target on the field, no hint
      #   element at all). See the class docs' "Filtering" section for why.
      def filter_min_chars_active?
        !!(@filter && @filter[:min_chars] && @filter[:auto] && frame?)
      end

      # @return [Hash] attributes for the filter toolbar's outer element
      #   (part :filter), merged with whatever the caller supplied via
      #   filter_html:.
      def filter_attributes
        html_for(:filter, class: filter_wrapper_class)
      end

      # @return [Hash] attributes for the filter toolbar's <form> (part
      #   :filter_form): method, action (when url: was given), a translated
      #   aria-label, and -- when the form is auto-submitting -- the
      #   tabler-ui--filter Stimulus wiring, plus -- when frame: is given --
      #   data-turbo-frame targeting the frame. Merged with whatever the
      #   caller supplied via filter_form_html:.
      def filter_form_attributes
        defaults = {
          class: "row g-2 align-items-end",
          method: @filter[:method].to_s,
          aria: { label: I18n.t("tabler_ui.table.filter_label") }
        }
        defaults[:action] = @filter[:url] if @filter[:url].present?

        # Both filter_auto_data_attributes and frame: contribute keys under
        # :data. A plain Hash#merge! here would let whichever applied second
        # replace :data outright and silently drop the other's keys --
        # TablerUi::HtmlOptions.merge_html deep-merges :data one level
        # instead, so the Stimulus controller/action keys and turbo_frame
        # targeting coexist.
        defaults = TablerUi::HtmlOptions.merge_html(defaults, filter_auto_data_attributes) if @filter[:auto]
        defaults = TablerUi::HtmlOptions.merge_html(defaults, data: { turbo_frame: @frame[:id] }) if frame?

        html_for(:filter_form, defaults)
      end

      # @return [Array<[String, Object]>] the hidden name/value pairs to
      #   render as hidden inputs -- entries with a nil/blank value are
      #   skipped so a GET form doesn't grow empty query params.
      def filter_hidden_fields
        return [] unless @filter

        @filter[:hidden].reject { |_, value| value.blank? }.to_a
      end

      # @return [Array<Hash>] normalized filter field definitions, ready to render
      def filter_fields
        @filter ? @filter[:fields] : []
      end

      # @param field [Hash] a normalized filter field
      # @return [String] the field's column-wrapper class -- the field's own
      #   :col overrides this outright (it's a plain default, not a rule 5
      #   hook, so no merge)
      def filter_field_wrapper_class(field)
        return field[:col] if field[:col].present?

        GROWING_FILTER_FIELD_TYPES.include?(field[:type]) ? "col-12 col-md" : "col-12 col-md-auto"
      end

      # @param field [Hash] a normalized filter field (:type in
      #   :search/:text/:date)
      # @return [Hash] attributes for the field's `<input>`, merged with the
      #   field's own html:. Carries the tabler-ui--filter Stimulus "input"
      #   target when this is the field filter: { min_chars: } applies to.
      def filter_field_input_attributes(field)
        base = {
          type: field[:type].to_s,
          class: "form-control",
          id: field[:id],
          name: field[:name],
          value: field[:value]
        }
        base[:placeholder] = field[:placeholder] if field[:placeholder].present?
        base[:data] = { "tabler-ui--filter-target": "input" } if field[:min_chars_target] && filter_min_chars_active?

        TablerUi::HtmlOptions.merge_html(base, field[:html])
      end

      # @param field [Hash] a normalized filter field carrying button: (see
      #   #build_filter_field)
      # @return [Hash] attributes for the field's attached search button
      #   (part :filter_button): class, type="submit". Merged with whatever
      #   the caller supplied via filter_button_html:.
      def filter_field_button_attributes(field)
        html_for(:filter_button, class: "btn", type: "submit")
      end

      # @param field [Hash] a normalized filter field
      # @return [Boolean] whether this field renders the filter: {
      #   min_chars: } hint -- true only for the single field min_chars:
      #   applies to (see #mark_min_chars_target!), AND only when
      #   min_chars: is actually active (see #filter_min_chars_active?).
      def filter_field_hint?(field)
        !!field[:min_chars_target] && filter_min_chars_active?
      end

      # @return [String] the filter: { min_chars: } hint text -- the
      #   caller's own min_chars_hint:, or a translated default
      #   interpolating the threshold
      def filter_min_chars_hint
        @filter[:min_chars_hint] || I18n.t("tabler_ui.table.min_chars_hint", count: @filter[:min_chars])
      end

      # @param field [Hash] a normalized filter field (unused directly --
      #   kept for symmetry with the other filter_field_*_attributes
      #   methods, and so a future per-field hint can vary this)
      # @return [Hash] attributes for the filter: { min_chars: } hint
      #   element (part :filter_hint): class="invalid-feedback", the
      #   tabler-ui--filter Stimulus "hint" target. Merged with whatever the
      #   caller supplied via filter_hint_html:.
      def filter_field_hint_attributes(field)
        html_for(:filter_hint, class: "invalid-feedback", data: { "tabler-ui--filter-target": "hint" })
      end

      # @param field [Hash] a normalized filter field (:type :select)
      # @return [Hash] attributes for the field's `<select>` (name/value are
      #   supplied directly to select_tag by the partial, not here -- see
      #   the rating component for the same split), merged with the field's
      #   own html:.
      def filter_field_select_attributes(field)
        TablerUi::HtmlOptions.merge_html({ class: "form-select", id: field[:id] }, field[:html])
      end

      # @return [Boolean] whether the Apply button renders -- only for a
      #   non-auto-submitting form
      def filter_show_submit?
        @filter && !@filter[:auto]
      end

      # @return [Boolean] whether the Reset link renders
      def filter_show_reset?
        @filter && @filter[:reset].present?
      end

      # @return [Boolean] whether the trailing button column renders at all
      def filter_show_buttons?
        filter_show_submit? || filter_show_reset?
      end

      # @return [String] the Apply button's label -- the caller's submit:,
      #   or a translated default
      def filter_submit_label
        @filter[:submit] || I18n.t("tabler_ui.table.apply")
      end

      # @return [String] the Reset link's translated label
      def filter_reset_label
        I18n.t("tabler_ui.table.reset")
      end

      # @return [String, nil] the Reset link's target URL
      def filter_reset_url
        @filter && @filter[:reset]
      end

      # @return [Hash] attributes for the Reset link (part :filter_reset):
      #   class, href, plus -- when frame: is given -- data-turbo-frame
      #   targeting the frame (mirroring #filter_form_attributes). Merged
      #   with whatever the caller supplied via filter_reset_html:.
      def filter_reset_attributes
        defaults = { class: "btn btn-link", href: filter_reset_url }
        defaults[:data] = { turbo_frame: @frame[:id] } if frame?

        html_for(:filter_reset, defaults)
      end

      # Guards the mutual exclusion between the declarative fields: and the
      # filter slot escape hatch -- mirrors pagination's computed-vs-builder
      # guard (#guard_against_computed! there). Called from the partial once
      # it knows whether the caller's block set the :filter slot, since that
      # isn't known until the block has run.
      #
      # @param has_slot [Boolean] whether slots.filter { ... } was set
      def guard_filter_slot!(has_slot)
        return unless has_slot && @filter && @filter[:fields].present?

        raise ArgumentError,
              "table filter: was given both fields: and a filter slot -- pick one: fields: for " \
              "the generated form, or slots.filter { ... } to supply the form contents yourself"
      end

      # --- Turbo Frames ------------------------------------------------------

      # @return [Boolean] whether frame: was given at all
      def frame?
        !@frame.nil?
      end

      # @return [Hash] attributes for the `<turbo-frame>` element (part
      #   :frame): id, data-turbo-action="advance" when advance: is true
      #   (the default), src:/loading: when given. Merged with whatever the
      #   caller supplied via frame_html:.
      def frame_attributes
        defaults = { id: @frame[:id] }
        defaults[:data] = { turbo_action: "advance" } if @frame[:advance]
        defaults[:src] = @frame[:src] if @frame[:src].present?
        defaults[:loading] = @frame[:loading].to_s if @frame[:loading]

        html_for(:frame, defaults)
      end

      # --- Footer ------------------------------------------------------------

      # @return [Hash] attributes for the footer slot's wrapping element
      #   (part :footer): class only (#footer_wrapper_class). Merged with
      #   whatever the caller supplied via footer_html:. Whether this
      #   actually renders is a partial-level question -- unlike every other
      #   *_attributes method here, there is no footer? on the component,
      #   because the component itself never sees the block/slots; the
      #   partial calls this only after checking `slots.present?(:footer)`
      #   itself (mirroring how it already checks `slots.present?(:filter)`
      #   for the filter slot).
      def footer_attributes
        html_for(:footer, class: footer_wrapper_class)
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

      # --- Sorting ---------------------------------------------------------

      # @param value [Hash, nil] the raw sort: option
      # @return [Hash, nil] `{ key:, dir: }` with dir validated/defaulted to
      #   :asc, or nil (unsorted) when value is nil or carries no :key
      def normalize_sort(value)
        return nil if value.nil? || value[:key].nil?

        { key: value[:key], dir: validate_sort_dir!(value[:dir] || :asc) }
      end

      def validate_sort_dir!(dir)
        dir = dir.to_s.to_sym
        return dir if SORT_DIRS.include?(dir)

        raise ArgumentError, "unknown table sort dir #{dir.inspect} -- valid: #{SORT_DIRS.join(', ')}"
      end

      # Raises ArgumentError if any column has a present sort: but sort_url:
      # was not given -- there would be nowhere for its header link to
      # point. A column with `sort: nil` does not trigger this -- see
      # #sortable?.
      def guard_sort_url!
        return unless @columns.any? { |col| col[:sort].present? }
        return if @sort_url

        raise ArgumentError,
              "table has a column with sort: but no sort_url: was given -- sort_url: is " \
              "required to build sortable header links"
      end

      # @param col [Hash] a column definition from :columns
      # @return [String] the direction sort_url: WOULD be called with if
      #   this column's header link were followed -- see the class docs'
      #   "Sorting" section for the cycle.
      def next_sort_dir(col)
        return :asc unless sorted?(col)
        return :desc if @sort[:dir] == :asc

        @sort_reset ? nil : :asc
      end

      # @param col [Hash] a column definition from :columns
      # @return [String, nil] this column's header link href, via sort_url:
      def sort_url_for(col)
        @sort_url.call(col[:sort], next_sort_dir(col))
      end

      # @param col [Hash] a column definition from :columns
      # @return [String] "table-sort", plus "asc"/"desc" when this is the
      #   currently sorted column
      def sort_link_classes(col)
        classes = ["table-sort"]
        classes << @sort[:dir].to_s if sorted?(col)
        classes.join(" ")
      end

      # --- Filtering ---------------------------------------------------------

      # @param filter_options [Hash, nil] the raw filter: option
      # @return [Hash, nil] the normalized filter state used by every
      #   filter_* method, or nil when filter: was not given
      def build_filter(filter_options)
        return nil if filter_options.nil?

        method = validate_filter_method!(filter_options[:method])
        # Default true only for a :get form on a framed table -- the one
        # combination where an auto-submit lands in a Turbo Frame swap
        # rather than a full navigation. See the :auto class docs above.
        auto = filter_options.key?(:auto) ? !!filter_options[:auto] : (method == :get && frame?)
        fields = (filter_options[:fields] || []).map { |field| build_filter_field(field) }
        min_chars = validate_min_chars!(filter_options[:min_chars], fields: fields)
        mark_min_chars_target!(fields, min_chars)

        {
          url: filter_options[:url],
          method: method,
          auto: auto,
          hidden: filter_options[:hidden] || {},
          reset: filter_options[:reset],
          submit: filter_options[:submit],
          debounce: filter_options[:debounce],
          min_chars: min_chars,
          min_chars_hint: filter_options[:min_chars_hint],
          fields: fields
        }
      end

      # @param value [Integer, nil] the raw filter: { min_chars: } option
      # @param fields [Array<Hash>] the already-normalized filter fields --
      #   used to check a :search/:text field exists for min_chars: to apply to
      # @return [Integer, nil] value, validated, or nil when not given
      #
      # Deliberately does NOT check auto:/frame: here -- whether min_chars:
      # actually takes effect is a rendering-time question (see
      # #filter_min_chars_active?), not a construction-time error. Only a
      # structurally broken call (not a positive Integer, or no
      # :search/:text field to attach to) raises.
      def validate_min_chars!(value, fields:)
        return nil if value.nil?

        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError, "table filter min_chars: must be a positive Integer, got #{value.inspect}"
        end

        unless fields.any? { |field| GROWING_FILTER_FIELD_TYPES.include?(field[:type]) }
          raise ArgumentError,
                "table filter min_chars: needs a search or text field to apply to, but fields: has none"
        end

        value
      end

      # Marks the first :search/:text field in +fields+ as the min_chars:
      # target (mutates it in place) -- that field is the one that gets the
      # tabler-ui--filter Stimulus "input" target and the trailing hint
      # element. No-op when min_chars is nil (min_chars: not given).
      #
      # @param fields [Array<Hash>] the already-normalized filter fields
      # @param min_chars [Integer, nil] the validated min_chars: value
      def mark_min_chars_target!(fields, min_chars)
        return unless min_chars

        target = fields.find { |field| GROWING_FILTER_FIELD_TYPES.include?(field[:type]) }
        target[:min_chars_target] = true
      end

      def validate_filter_method!(value)
        return :get if value.nil?

        method = value.to_sym
        return method if FILTER_METHODS.include?(method)

        raise ArgumentError, "unknown table filter method #{value.inspect} -- valid: #{FILTER_METHODS.join(', ')}"
      end

      # @return [Hash] the data-* attributes for the tabler-ui--filter
      #   Stimulus controller (already shipped by this gem), built with the
      #   data: hash form so they merge properly under filter_form_html:.
      def filter_auto_data_attributes
        data = {
          controller: "tabler-ui--filter",
          action: "input->tabler-ui--filter#submit change->tabler-ui--filter#submit"
        }
        data["tabler-ui--filter-debounce-value"] = @filter[:debounce] if @filter[:debounce]
        data["tabler-ui--filter-min-chars-value"] = @filter[:min_chars] if filter_min_chars_active?

        { data: data }
      end

      # @return [String] the filter toolbar's own base class -- differs by
      #   card: since a card: false table has no card shell for it to sit
      #   inside (see the class docs' "CARD INTERACTION" behaviour)
      def filter_wrapper_class
        card? ? "card-body border-bottom py-3" : "mb-3"
      end

      # --- Footer ------------------------------------------------------------

      # @return [String] the footer slot's own base class -- mirrors
      #   #filter_wrapper_class's card:-aware switch: a real `.card-footer`
      #   inside the `.card` shell, `mt-3` when `card: false` has no shell
      #   for it to sit inside.
      def footer_wrapper_class
        card? ? "card-footer" : "mt-3"
      end

      # @param field [Hash] a raw field hash from filter: { fields: [...] }
      # @return [Hash] the normalized field, with :type validated/defaulted,
      #   a deterministic :id for label binding (the field's own :id, when
      #   present, wins outright), :placeholder defaulted (search only),
      #   :button validated (search/text only), and (select fields only)
      #   :select_choices built from :options/:include_blank
      def build_filter_field(field)
        name = field[:name]
        raise ArgumentError, "table filter field is missing name: -- #{field.inspect}" if name.blank?

        type = validate_filter_field_type!(field[:type])
        button = field[:button]
        if button.present? && !GROWING_FILTER_FIELD_TYPES.include?(type)
          raise ArgumentError,
                "table filter field button: is only valid for :search/:text fields, not #{type.inspect} " \
                "-- there is nothing sensible for the button to attach to"
        end

        normalized = {
          name: name,
          type: type,
          id: field[:id].presence || filter_field_id(name),
          label: field[:label],
          value: field[:value],
          placeholder: filter_field_placeholder(field, type),
          col: field[:col],
          html: field[:html],
          button: button
        }
        normalized[:select_choices] = build_select_choices(field[:options], field[:include_blank]) if type == :select

        normalized
      end

      def validate_filter_field_type!(value)
        return :search if value.nil?

        type = value.to_sym
        return type if FILTER_FIELD_TYPES.include?(type)

        raise ArgumentError,
              "unknown table filter field type #{value.inspect} -- valid: #{FILTER_FIELD_TYPES.join(', ')}"
      end

      def filter_field_id(name)
        "table-filter-#{name.to_s.parameterize.presence || 'field'}"
      end

      # @param field [Hash] the raw field hash
      # @param type [Symbol] the field's validated :type
      # @return [String, nil] the field's placeholder -- the caller's own
      #   placeholder: if given (even if blank), else a translated default
      #   for :search only, else nil
      def filter_field_placeholder(field, type)
        return field[:placeholder] if field.key?(:placeholder)
        return I18n.t("tabler_ui.table.search_placeholder") if type == :search

        nil
      end

      # @param options [Array, nil] :options from a select field -- either
      #   [label, value] pairs or plain values (label == value)
      # @param include_blank [Boolean, String, nil] adds a blank option:
      #   `true` for an empty label, a String for a labelled blank option
      # @return [Array<Array(String, Object)>] choices ready for
      #   options_for_select
      def build_select_choices(options, include_blank)
        choices = Array(options).map { |option| option.is_a?(Array) ? option : [option, option] }
        return choices unless include_blank

        blank_label = include_blank == true ? "" : include_blank.to_s
        [[blank_label, ""]] + choices
      end

      # --- Turbo Frames ------------------------------------------------------

      # @param frame_options [String, Hash, nil] the raw frame: option -- a
      #   String is shorthand for `{ id: the String }`
      # @return [Hash, nil] the normalized frame state used by #frame_attributes
      #   and every frame-aware filter_* method, or nil when frame: was not given
      def build_frame(frame_options)
        normalized = TablerUi::Frame.normalize(frame_options, context: "table")
        return nil if normalized.nil?

        {
          id: normalized[:id],
          advance: normalized.fetch(:advance, true),
          src: normalized[:src],
          loading: validate_frame_loading!(normalized[:loading])
        }
      end

      def validate_frame_loading!(value)
        return nil if value.nil?

        loading = value.to_sym
        return loading if FRAME_LOADING_VALUES.include?(loading)

        raise ArgumentError,
              "unknown table frame loading #{value.inspect} -- valid: #{FRAME_LOADING_VALUES.join(', ')}"
      end
    end
  end
end
