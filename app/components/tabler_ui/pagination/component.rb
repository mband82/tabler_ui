# frozen_string_literal: true

module TablerUi
  module Pagination
    # Pagination component for Tabler UI. Builder-style: the block yields the
    # component itself, entries added via #item / #gap / #prev / #next.
    #
    # A second, more common way in: pass `current:`/`total:` and it works
    # out the item list itself -- see "Computed mode" below.
    #
    # This component never touches a collection, an ORM, or `params`. Its
    # entire input is two integers and a way to build a URL (`url:`, a
    # callable taking a page number).
    #
    # @example Builder mode -- full manual control
    #   <%= tabler_ui.pagination do |p| %>
    #     <% p.prev url: prev_path %>
    #     <% p.item 1, url: page_path(1) %>
    #     <% p.gap %>
    #     <% p.item 3, url: page_path(3), active: true %>
    #     <% p.item 4, url: page_path(4) %>
    #     <% p.next url: next_path %>
    #   <% end %>
    #
    # @example Computed mode -- the common case
    #   <%= tabler_ui.pagination current: 3, total: 10, url: ->(n) { posts_path(page: n) } %>
    #
    # @example size:, circle:, outline:
    #   <%= tabler_ui.pagination current: 1, total: 5, url: ->(n) { "?page=#{n}" },
    #                            size: :sm, circle: true %>
    #
    # @example Rule 5 hooks -- root and per-item
    #   <%= tabler_ui.pagination(html: { class: "mb-3" }) do |p| %>
    #     <% p.item 1, url: "/1", html: { class: "fw-bold" } %>
    #     <% p.item 2, url: "/2", html: ->(item) { { class: "text-danger" } if item.page == 2 } %>
    #   <% end %>
    #
    # @example frame: -- target a Turbo Frame that a framed table lives in
    #   <%= tabler_ui.pagination current: 3, total: 10, url: ->(n) { posts_path(page: n) },
    #                            frame: "posts-table" %>
    #
    # @example link_html: -- Rule 5 hook on the `<a>`/`<span>` element itself
    #   <%= tabler_ui.pagination current: 3, total: 10, url: ->(n) { posts_path(page: n) },
    #                            link_html: { class: "fw-bold" } %>
    #
    # ## Computed mode
    #
    # `current:` (1-based) and `total:` (page count) turn on computed mode:
    # the page range is worked out automatically. `window:` (default 2)
    # controls how many pages either side of `current` are shown; `url:` is
    # called once per link actually rendered (never for a gap or a disabled
    # prev/next).
    #
    # `current:`/`total:` and a block are mutually exclusive -- calling any
    # builder method (#item/#gap/#prev/#next) while computed options were
    # given raises ArgumentError immediately. A block that never calls a
    # builder method (or no block at all) is fine either way.
    #
    # `current:` given without `total:` also raises.
    #
    # ### Degenerate totals
    #
    # `total: 0` renders an empty `<ul class="pagination">` -- nothing to
    # paginate, no error. `current:` is ignored in this case.
    #
    # `total: 1` renders a single active page 1 with both prev and next
    # disabled, rather than nothing, keeping the markup shape uniform.
    #
    # Any other `current:` outside `1..total` raises ArgumentError.
    #
    # ## The range algorithm
    #
    # Always shows page 1 and the last page, plus a window of `window:`
    # pages either side of `current`, clamped to `1..total`. A single
    # hidden page between two shown ones is shown outright instead of a
    # gap; two or more hidden pages collapse to one `:gap` marker.
    #
    # ## Turbo Frames
    #
    # `table`'s `frame:` *emits* a `<turbo-frame>`; pagination's `frame:`
    # (same key, different job) makes every rendered link *target* one by
    # id, via `data-turbo-frame="<id>"` -- pagination never emits a
    # `<turbo-frame>` of its own:
    #
    #   <%= tabler_ui.table columns: columns, data: rows, frame: "users-table" %>
    #   <%= tabler_ui.pagination current: page, total: total,
    #                            url: ->(n) { users_path(page: n) },
    #                            frame: "users-table" %>
    #
    # Only `id:` is accepted; `advance:`/`src:`/`loading:` belong to
    # `table`'s `frame:` and are silently ignored here. No `turbo-rails`
    # dependency -- `data-turbo-frame` is inert markup without Turbo loaded
    # in the host app.
    #
    # ## page-prev / page-next
    #
    # Tabler's `.page-prev`/`.page-next` classes are `flex: 0 0 50%` each
    # (built for a two-item "‹ Previous / Next ›" pager) -- combining them
    # with page-number items overflows the container, so they're applied
    # only when this is a pure prev/next pager with no `:page` items. Any
    # pager with page numbers -- every computed-mode render included --
    # falls back to plain `page-item`.
    #
    # ## CSS surface
    #
    #   ul.pagination[.pagination-sm|.pagination-lg][.pagination-circle][.pagination-outline]
    #     li.page-item[.active][.disabled][.page-prev|.page-next -- prev/next-only pagers, see above]
    #       a.page-link (linkable items) or span.page-link (gaps, disabled prev/next)
    #
    # ## Accessibility
    #
    # The `<ul class="pagination">` is wrapped in a `<nav>` landmark with a
    # translated `aria-label`. The active page's `<li>` gets
    # `aria-current="page"`. An item only renders as `<a>` when it has a URL
    # *and* isn't disabled -- disabled prev/next and gaps render as
    # `<span class="page-link">` instead, so they are never focusable.
    class Component
      include TablerUi::Base
      builder_style!

      SIZES = %i[sm lg].freeze

      # :html holds the caller's *raw* per-item hook (Hash or Proc taking the
      # item), not resolved attributes -- see #item_attributes. :kind is one
      # of :page, :gap, :prev, :next. :page/:active only mean anything for
      # :page items; :label only for :prev/:next (falls back to the
      # component-level prev_label:/next_label: option, then to a translated
      # default -- see #item_text).
      Item = Struct.new(:kind, :page, :label, :url, :active, :disabled, :html, keyword_init: true)

      attr_reader :items, :size, :circle, :outline, :window, :frame

      # @param options [Hash]
      # @option options [Integer] :current 1-based current page. Switches on
      #   computed mode together with :total -- see the class docs. Defaults
      #   to 1 when :total is given without it.
      # @option options [Integer] :total Total page count. Switches on
      #   computed mode. Mandatory if :current is given.
      # @option options [Integer] :window Pages shown either side of
      #   :current in computed mode (default: 2).
      # @option options [#call] :url Computed mode only -- a callable taking
      #   a page number and returning its URL.
      # @option options [Symbol, String] :size One of :sm, :lg -- pagination-sm/-lg.
      # @option options [Boolean] :circle Pill-shaped items -- pagination-circle.
      # @option options [Boolean] :outline Bordered items -- pagination-outline.
      # @option options [String] :prev_label Component-wide default text for
      #   the prev control (falls back to a translated default). A per-call
      #   `label:` passed to #prev overrides this.
      # @option options [String] :next_label Same as :prev_label, for #next.
      # @option options [String, Hash] :frame Opt-in Turbo Frame *targeting*
      #   -- see "Turbo Frames" above. A String is shorthand for `{ id: the
      #   String }`. `id:` is mandatory (raises ArgumentError when blank);
      #   `advance:`/`src:`/`loading:` are ignored if given -- those belong
      #   to `table`'s `frame:` alone. Absent (the default) renders no
      #   `data-turbo-frame` attribute at all; the rest of the component's
      #   output is unaffected.
      # @option options [Hash] :html Rule 5 HTML hook for the `<ul class="pagination">` (part :root)
      # @option options [Hash, #call] :item_html Rule 5 HTML hook applied to
      #   every `<li class="page-item">` (part :item) -- a plain Hash, or a
      #   callable taking the item. Merged underneath any per-item `html:`
      #   given to #item/#prev/#next directly.
      # @option options [Hash, #call] :link_html Rule 5 HTML hook applied to
      #   every `<a class="page-link">`/`<span class="page-link">` (part
      #   :link) -- a plain Hash, or a callable taking the item, same
      #   contract as :item_html.
      def initialize(options = {})
        @computed = options.key?(:total) || options.key?(:current)
        @size = validate_size!(options[:size])
        @circle = options[:circle]
        @outline = options[:outline]
        @window = options.fetch(:window, 2)
        @prev_label = options[:prev_label]
        @next_label = options[:next_label]
        @frame = build_frame(options[:frame])
        @items = []

        initialize_html_options(options)

        return unless @computed

        unless options.key?(:total)
          raise ArgumentError,
                "pagination current: was given without total: -- computed mode needs both " \
                "to work out a page range"
        end

        @total = options[:total]
        @current = options.fetch(:current, 1)
        @url_proc = options[:url]

        validate!
        build_computed!
      end

      # Adds a page entry.
      #
      # @param page [Integer] Page number, also used as the link text
      # @param options [Hash]
      # @option options [String] :url Page URL. When absent, the item renders
      #   as plain (non-focusable) text instead of a link.
      # @option options [Boolean] :active Marks this as the current page --
      #   drives the `active` class and `aria-current="page"`.
      # @option options [Boolean] :disabled Forces the item to render as
      #   non-linkable text even if a :url was given.
      # @option options [Hash, #call] :html Rule 5 HTML hook for this item's
      #   `<li class="page-item">` (part :item) -- a plain Hash, or a
      #   callable taking the item
      # @return [String] empty string, to avoid stray output in a capture context
      def item(page, options = {})
        builder_argument!(page, :page, builder: :item)
        guard_against_computed!(:item)

        add_page(page, options)
      end

      # Adds a gap ("...") between page entries. Always renders as
      # non-linkable text.
      #
      # @return [String] empty string, to avoid stray output in a capture context
      def gap
        guard_against_computed!(:gap)

        add_gap
      end

      # Adds the "previous page" control.
      #
      # @param options [Hash]
      # @option options [String] :url Target URL. When absent (or when
      #   :disabled), renders as plain (non-focusable) text.
      # @option options [Boolean] :disabled Forces non-linkable text.
      # @option options [String] :label Link text (default: the component's
      #   prev_label: option, then a translated "Previous").
      # @option options [Hash, #call] :html Rule 5 HTML hook for this item's
      #   `<li class="page-item">` (part :item) -- gains `page-prev` too, but
      #   only when this is a prev/next-only pager with no #item calls; see
      #   "page-prev / page-next" above.
      # @return [String] empty string, to avoid stray output in a capture context
      def prev(options = {})
        guard_against_computed!(:prev)

        add_prev(options)
      end

      # Adds the "next page" control. See #prev -- same shape, opposite end.
      #
      # @return [String] empty string, to avoid stray output in a capture context
      def next(options = {})
        guard_against_computed!(:next)

        add_next(options)
      end

      # Called by TablerUi::Ui once a builder block has run (see
      # `lib/tabler_ui/ui.rb#render_block`), and by #initialize itself in
      # computed mode (which knows its full range immediately and doesn't
      # need to wait for a block). A no-op outside computed mode -- builder
      # mode has no component-wide "current page index" to range-check,
      # only per-item `active:` flags.
      def validate!
        return unless @computed
        return if @total.to_i <= 0
        return if (1..@total).cover?(@current)

        raise ArgumentError,
              "pagination current: #{@current.inspect} is out of range -- valid: 1..#{@total}"
      end

      # @return [Hash] attributes for the `<ul class="pagination">` (part :root)
      def root_attributes
        html_for(:root, class: root_classes)
      end

      # @param item [Item] the item being rendered
      # @return [Hash] attributes for this item's `<li>` (part :item),
      #   merging three layers in order: the item's own base classes/aria,
      #   then the component-level `item_html:` hook (a Hash applied to
      #   every item, or a callable taking the item -- the `table#row_html:`
      #   pattern, since computed mode never calls #item/#prev/#next itself
      #   so there is no per-call site to hang a hook on), then this
      #   particular item's own `html:` (set via #item/#prev/#next in
      #   builder mode -- the `breadcrumb#item` pattern). The item's own
      #   `html:` wins when both are given.
      def item_attributes(item)
        defaults = { class: item_classes(item) }
        defaults[:"aria-current"] = "page" if current_page?(item)

        TablerUi::HtmlOptions.merge_html(html_for(:item, defaults, item), resolve(item.html, item))
      end

      # @param item [Item] the item being tested
      # @return [Boolean] whether this item renders as `<a>` (true) or
      #   `<span>` (false, never focusable) -- needs a URL and must not be
      #   explicitly disabled.
      def linkable?(item)
        item.url.present? && !item.disabled
      end

      # @param item [Item] the item being rendered
      # @return [Hash] attributes for this item's `<a>` (#linkable? item) or
      #   `<span>` (gap, disabled prev/next) element (part :link) -- one
      #   method covers both tags since they are the same visual element,
      #   just without an `href` (and hence without a real destination) when
      #   there's nothing to link to. Always carries "page-link"; gains
      #   `href:` when #linkable?(item), and `data-turbo-frame` when the
      #   component-level `frame:` option was given (see "Turbo Frames"
      #   above) -- but only on the real links. A gap or a disabled prev/next
      #   renders as a `<span>` with no `href` and never navigates anywhere,
      #   so a `data-turbo-frame` there would be inert markup repeated on
      #   every page of every paginated list.
      def link_attributes(item)
        defaults = { class: "page-link" }

        if linkable?(item)
          defaults[:href] = item.url
          defaults[:data] = { turbo_frame: frame[:id] } if frame
        end

        html_for(:link, defaults, item)
      end

      # @param item [Item] the item being rendered
      # @return [String] this item's visible/link text
      def item_text(item)
        case item.kind
        when :page then item.page.to_s
        when :gap then I18n.t("tabler_ui.pagination.gap")
        when :prev then item.label || prev_label
        when :next then item.label || next_label
        end
      end

      # @return [String] translated aria-label for the `<nav>` landmark
      def aria_label
        I18n.t("tabler_ui.pagination.aria_label")
      end

      private

      # @param hook [Hash, #call, nil] a raw rule-5 hook value
      # @param item [Item] passed to +hook+ when it's callable
      # @return [Hash] the hook resolved to a plain Hash, ready for merge_html
      def resolve(hook, item)
        hook.respond_to?(:call) ? hook.call(item) : hook
      end

      # @param item [Item] the item being tested
      # @return [Boolean] whether this is the active :page item
      def current_page?(item)
        item.kind == :page && item.active
      end

      def prev_label
        @prev_label || I18n.t("tabler_ui.pagination.prev")
      end

      def next_label
        @next_label || I18n.t("tabler_ui.pagination.next")
      end

      # Guards the public builder methods (#item/#gap/#prev/#next) against
      # being called from a caller's block when computed options were also
      # given -- see the class docs' "Computed mode" section. #build_computed!
      # bypasses this by calling #add_page/#add_gap/#add_prev/#add_next
      # directly.
      def guard_against_computed!(builder)
        return unless @computed

        raise ArgumentError,
              "pagination current:/total: and a block are mutually exclusive -- " \
              "got both computed options and a manual ##{builder} call"
      end

      def add_page(page, options = {})
        @items << Item.new(kind: :page, page: page, url: options[:url], active: options[:active],
                            disabled: options[:disabled], html: options[:html])
        ""
      end

      def add_gap
        @items << Item.new(kind: :gap, disabled: true)
        ""
      end

      def add_prev(options = {})
        @items << Item.new(kind: :prev, label: options[:label], url: options[:url],
                            disabled: options[:disabled], html: options[:html])
        ""
      end

      def add_next(options = {})
        @items << Item.new(kind: :next, label: options[:label], url: options[:url],
                            disabled: options[:disabled], html: options[:html])
        ""
      end

      # Builds the full item list for computed mode, on top of the same
      # #add_page/#add_gap/#add_prev/#add_next primitives the guarded public
      # builder methods use. Total <= 0 leaves @items empty (see the class
      # docs' "Degenerate totals" section).
      def build_computed!
        return if @total.to_i <= 0

        prev_disabled = @current <= 1
        next_disabled = @current >= @total

        add_prev(url: prev_disabled ? nil : url_for(@current - 1), disabled: prev_disabled)

        compute_pages.each do |page|
          if page == :gap
            add_gap
          else
            add_page(page, url: url_for(page), active: page == @current)
          end
        end

        add_next(url: next_disabled ? nil : url_for(@current + 1), disabled: next_disabled)
      end

      # @param page [Integer] page number
      # @return [String, nil] the page's URL, via the caller's :url callable
      #   -- nil if no :url was given
      def url_for(page)
        @url_proc&.call(page)
      end

      # Works out which page numbers to show, and where the gaps go. Page 1
      # and @total are always shown, plus a window: of @window pages either
      # side of @current, clamped to 1..@total. A run of exactly one hidden
      # page between two shown ones is shown outright instead of becoming a
      # :gap -- see the class docs' "The range algorithm" section.
      #
      # @return [Array<Integer, Symbol>] page numbers interspersed with :gap markers
      def compute_pages
        window_start = [@current - @window, 1].max
        window_end = [@current + @window, @total].min
        shown = ([1] + (window_start..window_end).to_a + [@total]).uniq.sort

        pages = []
        previous = nil

        shown.each do |page|
          if previous
            hidden = page - previous - 1
            pages << (previous + 1) if hidden == 1
            pages << :gap if hidden > 1
          end

          pages << page
          previous = page
        end

        pages
      end

      # @param value [String, Hash, nil] the raw :frame option
      # @return [Hash, nil] `{ id: }` normalized, or nil when :frame was not
      #   given at all. A String is shorthand for `{ id: the String }`.
      #   `advance:`/`src:`/`loading:` are silently ignored if present --
      #   see the class docs' "Turbo Frames" section for why.
      def build_frame(value)
        normalized = TablerUi::Frame.normalize(value, context: "pagination")
        return nil if normalized.nil?

        { id: normalized[:id] }
      end

      def validate_size!(value)
        return nil if value.nil?

        size = value.to_sym
        return size if SIZES.include?(size)

        raise ArgumentError,
              "unknown pagination size #{value.inspect} — valid: #{SIZES.join(', ')}"
      end

      def root_classes
        classes = ["pagination"]
        classes << "pagination-sm" if size == :sm
        classes << "pagination-lg" if size == :lg
        classes << "pagination-circle" if circle
        classes << "pagination-outline" if outline
        classes.join(" ")
      end

      def item_classes(item)
        classes = ["page-item"]
        classes << "page-prev" if item.kind == :prev && pure_prev_next?
        classes << "page-next" if item.kind == :next && pure_prev_next?
        classes << "active" if current_page?(item)
        classes << "disabled" if item.disabled
        classes.join(" ")
      end

      # @return [Boolean] whether this pager has no :page items -- i.e. is a
      #   pure prev/next "article" pager, the only shape #page-prev/#page-next
      #   are safe on (see "page-prev / page-next" in the class docs).
      #   Deliberately read from @items at call time rather than cached in
      #   #initialize -- in builder mode the full item list isn't known
      #   until the caller's block has finished running, and #item_classes
      #   (via #item_attributes) is only ever invoked at render time, after
      #   that block, so this always sees the final list.
      #
      #   Why this guard exists: Tabler's stylesheet defines
      #   `.page-item.page-prev`/`.page-item.page-next` for a completely
      #   different widget than this component's usual output -- the
      #   article-style "‹ PREVIOUS / *Article title*" pager, where prev and
      #   next are the *only* two items in the row. To make that work,
      #   Tabler gives each of them `flex: 0 0 50%` -- prev claims the left
      #   half of the row, next (`margin-left: auto`, right-aligned text)
      #   claims the right half. `.pagination` is a plain, non-wrapping flex
      #   row, so that 50/50 split is only correct when prev and next
      #   really are the only two items. The moment page-number items sit
      #   between them, prev + next alone already total 100% of the row's
      #   flex basis, and the numbers push `page-next` straight out past
      #   the container's right edge -- confirmed in a browser: Previous
      #   stays put, the numbers center themselves, and Next renders
      #   outside the card footer entirely.
      #
      #   Do not reinstate these classes unconditionally "to match Tabler's
      #   markup" -- that markup is for the article pager, not this one, and
      #   combining them with page numbers is precisely the overflow bug
      #   described above.
      def pure_prev_next?
        @items.none? { |i| i.kind == :page }
      end
    end
  end
end
