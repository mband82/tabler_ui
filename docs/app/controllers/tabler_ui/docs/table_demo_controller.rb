# frozen_string_literal: true

module TablerUi
  module Docs
    # Backs the table component's one genuinely stateful demo --
    # docs/lib/tabler_ui/docs/demos/table_demos.rb's :sort_filter_page --
    # sortable/filterable/paginated rows inside a Turbo Frame. The row data,
    # the whitelisted sort keys, the per-page size, and every bit of
    # sort/filter/paginate logic below are MOVED verbatim from
    # showcase/app/controllers/showcase_controller.rb's TABLE_DEMO_* constants
    # and private table_demo_* methods, not rewritten -- they were already
    # correct, already whitelist their inputs, and already survive junk
    # params (?page=abc, ?sort=zzz return 200, not 500). Only the entry point
    # changed, and only because it had to (see below).
    #
    # ## Why this controller exists, instead of expressing the whole demo
    # ## through Demo#locals
    #
    # docs/DEMOS.md ("Stateful demos: locals:") describes `locals:` as a
    # zero-argument Proc, called lazily by Demo#resolved_locals with no
    # arguments -- it has no access to a current request's `params`, because
    # nothing passes it any. That is confirmed, not assumed: every registered
    # demo's source is rendered by
    # spec/lib/tabler_ui/docs/demo_registry_spec.rb ("every registered demo
    # renders its source via render inline: without raising") through a bare
    # `ActionView::Base.with_empty_template_cache` with only TablerUi::Helper
    # mixed in -- no controller, no request, no route helpers. A demo's
    # `source:` calling `params` or a bare `table_demo_path` would raise
    # there. `locals:` can hand the ERB a *snapshot* (unsorted, unfiltered,
    # page 1 -- see the :sort_filter_page demo's `locals:`), and that
    # snapshot is genuinely correct for that spec and for a fresh page load,
    # but nothing under docs/lib/tabler_ui/docs/demos/*.rb can turn a live
    # click into a live request/response round trip -- that needs an actual
    # routed endpoint. This controller is that endpoint (GET /ui/table_demo,
    # see docs/config/routes.rb's `as: :table_demo`), and it's what the
    # demo's sort links, filter form and pager already point at -- built via
    # `Engine.routes.url_helpers.table_demo_path` below, never a bare
    # `table_demo_path`, so the same URL-building code works whether it's
    # called from this controller's own (route-helper-bearing) view or from
    # a demo's `locals:` Proc (which has neither).
    #
    # This gem takes no turbo-rails dependency (see the table component's
    # "Turbo Frames" docs), so nothing here special-cases a Turbo-Frame
    # request differently from a plain GET -- #show always renders the same
    # full view. Turbo only needs a response to contain an element whose id
    # matches the frame it navigated ("table-demo") *somewhere* in the
    # document to swap it in; it doesn't need (or want) a partial response,
    # so reusing the full show view for both a direct visit and a
    # frame-scoped navigation is correct, not a shortcut.
    class TableDemoController < ApplicationController
      # Moved verbatim from ShowcaseController::TABLE_DEMO_ROWS.
      TABLE_DEMO_ROWS = [
        { name: "Ada Lovelace", status: "active", created_at: Date.new(2026, 1, 12) },
        { name: "Grace Hopper", status: "active", created_at: Date.new(2025, 11, 3) },
        { name: "Alan Turing", status: "away", created_at: Date.new(2026, 2, 20) },
        { name: "Katherine Johnson", status: "active", created_at: Date.new(2025, 8, 30) },
        { name: "Margaret Hamilton", status: "inactive", created_at: Date.new(2026, 3, 5) },
        { name: "Radia Perlman", status: "away", created_at: Date.new(2025, 12, 18) },
        { name: "Barbara Liskov", status: "active", created_at: Date.new(2026, 4, 1) }
      ].freeze

      # Moved verbatim from ShowcaseController::TABLE_DEMO_SORT_KEYS.
      TABLE_DEMO_SORT_KEYS = %w[name status created_at].freeze

      # Moved verbatim from ShowcaseController::TABLE_DEMO_PER_PAGE.
      TABLE_DEMO_PER_PAGE = 3

      def show
        @table_demo_sort = self.class.table_demo_sort(params)
        @table_demo_page = self.class.table_demo_page(params)
        @table_demo_total_pages = self.class.table_demo_total_pages(params)
        @table_demo_rows = self.class.table_demo_rows(params)
        @table_demo_sort_url = self.class.table_demo_sort_url(params)
        @table_demo_pagination_url = self.class.table_demo_pagination_url(params)
      end

      class << self
        # Every method below takes an explicit `params`-like object (an
        # ActionController::Parameters from a real request, or a plain Hash
        # from a demo's `locals:` default snapshot) rather than reading a
        # `params` method off `self`, since a `locals:` Proc has no such
        # method to read. Both respond to `#[]`/`#present?` identically for
        # the plain reads this class does (no mass-assignment, nothing ever
        # permitted), so the two callers are interchangeable. This is the
        # one adaptation made porting this logic out of a controller's
        # instance context -- the sort/filter/paginate bodies themselves are
        # unchanged from ShowcaseController.

        # @return [Hash] { key:, dir: } -- see ShowcaseController#table_demo_sort.
        def table_demo_sort(params)
          key = params[:sort] if TABLE_DEMO_SORT_KEYS.include?(params[:sort])
          { key: key, dir: params[:dir] == "desc" ? "desc" : "asc" }
        end

        # @return [Array<Hash>] the current page's rows -- filtered, then
        # sorted, then sliced. See ShowcaseController#table_demo_rows.
        def table_demo_rows(params)
          rows = sort_table_demo_rows(table_demo_filtered_rows(params), table_demo_sort(params))
          offset = (table_demo_page(params) - 1) * TABLE_DEMO_PER_PAGE
          rows[offset, TABLE_DEMO_PER_PAGE] || []
        end

        # @return [Array<Hash>] TABLE_DEMO_ROWS after filtering. See
        # ShowcaseController#table_demo_filtered_rows.
        def table_demo_filtered_rows(params)
          filter_table_demo_rows(TABLE_DEMO_ROWS, params)
        end

        # @return [Integer] total pages for the *filtered* row count (never
        # less than 1). See ShowcaseController#table_demo_total_pages.
        def table_demo_total_pages(params)
          [(table_demo_filtered_rows(params).size / TABLE_DEMO_PER_PAGE.to_f).ceil, 1].max
        end

        # @return [Integer] the current page, clamped to 1..total_pages.
        # See ShowcaseController#table_demo_page.
        def table_demo_page(params)
          page = params[:page].to_i
          return 1 if page < 1

          [page, table_demo_total_pages(params)].min
        end

        # See ShowcaseController#filter_table_demo_rows.
        def filter_table_demo_rows(rows, params)
          if params[:q].present?
            term = params[:q].downcase
            rows = rows.select { |row| row[:name].downcase.include?(term) }
          end
          rows = rows.select { |row| row[:status] == params[:status] } if params[:status].present?
          rows
        end

        # See ShowcaseController#sort_table_demo_rows.
        def sort_table_demo_rows(rows, sort)
          return rows unless sort[:key]

          sorted = rows.sort_by { |row| row[sort[:key].to_sym] }
          sort[:dir] == "desc" ? sorted.reverse : sorted
        end

        # @return [#call] a sort_url: callable for tabler_ui.table -- ported
        # from the live block's `table_demo_sort_url` local
        # (showcase/app/views/showcase/layout.html.erb), built here with
        # `Engine.routes.url_helpers` instead of a bare `layout_path` so it
        # works from both this controller's own view and a demo's `locals:`.
        def table_demo_sort_url(params)
          ->(key, dir) {
            Engine.routes.url_helpers.table_demo_path(
              **{ sort: dir && key, dir: dir, q: params[:q], status: params[:status] }.compact_blank
            )
          }
        end

        # @return [#call] a pagination url: callable -- ported from the live
        # block's `table_demo_pagination_url` local, same reasoning as
        # #table_demo_sort_url above.
        def table_demo_pagination_url(params)
          sort = table_demo_sort(params)
          ->(page) {
            Engine.routes.url_helpers.table_demo_path(
              **{ sort: sort[:key], dir: sort[:dir], q: params[:q], status: params[:status], page: page }.compact_blank
            )
          }
        end

        # @return [String] the filter form's action -- ported from the live
        # block's `filter: { url: layout_path }`.
        def table_demo_filter_url
          Engine.routes.url_helpers.table_demo_path
        end

        # @return [String] the filter toolbar's Reset link -- ported from
        # the live block's `filter: { reset: layout_path(**{...}.compact_blank) }`.
        def table_demo_reset_url(params)
          sort = table_demo_sort(params)
          Engine.routes.url_helpers.table_demo_path(**{ sort: sort[:key], dir: sort[:dir] }.compact_blank)
        end
      end
    end
  end
end
