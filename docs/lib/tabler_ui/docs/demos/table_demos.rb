# frozen_string_literal: true

# Ported from showcase/app/views/showcase/layout.html.erb (the render layout:
# "showcase/example" blocks for "table - striped, hover, row_html:", "table -
# responsive: \"sm\"", "table - responsive: false", "table - mobile: true",
# "table - frame:", and "table - filter min_chars: 3, no frame:") -- the
# live example blocks, not SNIPPETS[:layout_5]/[:layout_22..24]/[:layout_28]/
# [:layout_29], per docs/DEMOS.md.
#
# Drift found:
#
# - :row_html (content_5/layout_5): SNIPPETS[:layout_5]'s Status column is
#   `tabler_ui.status(text: row[:status], dot: true)` -- no color:. The live
#   block's Status column is
#   `tabler_ui.status(text: row[:status], color: row[:status] == "Active" ? "success" : "secondary", dot: true)`.
#   The snippet's reader would see a plain-colored dot; the live example
#   actually renders green for "Active" rows and gray for everything else.
#   Ported from the live block, color: included.
# - :sort_filter_page (layout_28): the CONFIRMED drift called out in the
#   porting brief. SNIPPETS[:layout_28] inlines `sort_url: ->(key, dir) {
#   layout_path(sort: dir && key, dir: dir, q: params[:q], status:
#   params[:status]) }` and a matching inline pagination `url:` lambda,
#   built directly against `layout_path` with no `.compact_blank`. The live
#   block instead builds two named locals, `table_demo_sort_url` and
#   `table_demo_pagination_url`, each wrapping `layout_path(**{...}.compact_blank)`
#   -- `.compact_blank` drops nil/blank entries (an absent q:/status:, a nil
#   dir: when unsorted) before they ever reach `layout_path`, so the built
#   URL omits e.g. `?q=` entirely instead of carrying a blank query param.
#   The snippet is materially less defensive than what actually rendered.
#   Ported from the live block's shape -- see TableDemoController's
#   #table_demo_sort_url/#table_demo_pagination_url, which build the same
#   `**{...}.compact_blank` calls against the docs engine's own
#   `table_demo_path` instead of a bare `layout_path`.
#
# No other drift: :responsive_sm, :responsive_false, :mobile and
# :filter_no_frame's live blocks matched their SNIPPETS entries (modulo
# differences in surrounding local-variable names, which the old showcase
# page shared across several examples and this file does not) -- ported from
# the live block anyway per docs/DEMOS.md.
#
# One deliberate simplification, not a drift: the live :filter_no_frame block
# (content_29/layout_29) filtered its rows against a real `params[:inert_q]`
# (coerced with `.to_s` so the field's `value:` was never nil -- a minor
# further difference from SNIPPETS[:layout_29], which passed `params[:inert_q]`
# raw/possibly-nil). This demo's entire point is that the filter has NO
# effect without `auto:`+`frame:` together, so an actually-filtered result
# would demonstrate nothing that a static unfiltered table doesn't already
# show, and giving it real param-driven behaviour would mean either a second
# stateful backing route for a demo explicitly built to prove nothing
# happens live, or the same `params`-in-source problem :sort_filter_page
# above solves with a controller. Ported instead as a fully static,
# always-unfiltered snapshot -- self-contained literals, no `locals:` needed.
#
# ## The stateful demo: :sort_filter_page
#
# This is the one genuinely stateful demo in the whole layout page. Its
# state (which rows are shown, current sort/filter/page) cannot be expressed
# purely through `locals:` the way docs/DEMOS.md describes for the common
# case -- see docs/app/controllers/tabler_ui/docs/table_demo_controller.rb's
# class docs for exactly why (short version: `locals:` is a zero-argument
# Proc with no access to a request's `params`, and every registered demo's
# source is also rendered through a bare ActionView context with no request
# at all, by spec/lib/tabler_ui/docs/demo_registry_spec.rb -- so a demo's
# `source:` can never itself read `params` or call a bare route helper).
#
# What `locals:` CAN do, and does here, is supply a default snapshot: page
# 1, unsorted, unfiltered, using TablerUi::Docs::TableDemoController's own
# class methods fed a blank Hash instead of a real request's params (see
# TableDemoController for why a plain Hash and ActionController::Parameters
# are interchangeable for the reads those methods do). That snapshot is
# genuinely correct for a fresh page load. The live sorting/filtering/paging
# itself happens by the rendered table's links and form pointing at a real
# routed endpoint -- GET /ui/table_demo (docs/config/routes.rb, `as:
# :table_demo`) -- built via `Engine.routes.url_helpers.table_demo_path`,
# never a bare `table_demo_path`, so the same URL-building works whether
# it's this file's `locals:` Proc calling it (no controller, no route
# helpers mixed in) or TableDemoController's own view (which has both).
# TABLE_DEMO_ROWS, the sort-key whitelist, the page size, and every bit of
# sort/filter/paginate logic live on TableDemoController, MOVED verbatim
# from ShowcaseController's TABLE_DEMO_* constants and private table_demo_*
# methods -- not rewritten.
TablerUi::Docs::DemoRegistry.define(:table) do |c|
  c.demo :row_html,
         title: "striped, hover, row_html:",
         source: <<~'ERB'
           <% columns = [
             { label: "Name", value: ->(row) { row[:name] } },
             { label: "Role", value: ->(row) { row[:role] } },
             { label: "Status", class: "text-end",
               value: ->(row) { tabler_ui.status(text: row[:status], color: row[:status] == "Active" ? "success" : "secondary", dot: true) } }
           ] %>
           <% rows = [
             { name: "Ada Lovelace", role: "Engineer", status: "Active" },
             { name: "Grace Hopper", role: "Admiral", status: "Active" },
             { name: "Alan Turing", role: "Researcher", status: "Away" }
           ] %>
           <%= tabler_ui.table columns: columns, data: rows, striped: true, hover: true,
                               row_html: ->(row) { { class: "table-warning" } if row[:status] == "Away" } %>
         ERB

  c.demo :responsive_sm,
         title: "responsive: \"sm\" (scrolls only below sm, instead of at every width)",
         source: <<~'ERB'
           <% columns = [
             { label: "Name", value: ->(row) { row[:name] } },
             { label: "Role", value: ->(row) { row[:role] } },
             { label: "Status", class: "text-end",
               value: ->(row) { tabler_ui.status(text: row[:status], color: row[:status] == "Active" ? "success" : "secondary", dot: true) } }
           ] %>
           <% rows = [
             { name: "Ada Lovelace", role: "Engineer", status: "Active" },
             { name: "Grace Hopper", role: "Admiral", status: "Active" },
             { name: "Alan Turing", role: "Researcher", status: "Away" }
           ] %>
           <%= tabler_ui.table columns: columns, data: rows, responsive: "sm" %>
         ERB

  c.demo :responsive_false,
         title: "responsive: false (no scroll wrapper)",
         source: <<~'ERB'
           <% columns = [
             { label: "Name", value: ->(row) { row[:name] } },
             { label: "Role", value: ->(row) { row[:role] } },
             { label: "Status", class: "text-end",
               value: ->(row) { tabler_ui.status(text: row[:status], color: row[:status] == "Active" ? "success" : "secondary", dot: true) } }
           ] %>
           <% rows = [
             { name: "Ada Lovelace", role: "Engineer", status: "Active" },
             { name: "Grace Hopper", role: "Admiral", status: "Active" },
             { name: "Alan Turing", role: "Researcher", status: "Away" }
           ] %>
           <%= tabler_ui.table columns: columns, data: rows, responsive: false %>
         ERB

  c.demo :mobile,
         title: "mobile: true (card-stacked at all widths; data-label draws the headings)",
         source: <<~'ERB'
           <% mobile_columns = [
             { label: "Name", value: ->(row) { row[:name] } },
             { label: "Role", value: ->(row) { row[:role] } },
             { label: "Department", value: ->(row) { row[:department] } },
             { label: "Location", value: ->(row) { row[:location] } },
             { label: "Status", class: "text-end",
               value: ->(row) { tabler_ui.status(text: row[:status], color: row[:status] == "Active" ? "success" : "secondary", dot: true) } }
           ] %>
           <% mobile_rows = [
             { name: "Ada Lovelace", role: "Engineer", department: "Platform", location: "London", status: "Active" },
             { name: "Grace Hopper", role: "Admiral", department: "Navy", location: "Virginia", status: "Active" },
             { name: "Alan Turing", role: "Researcher", department: "Cryptography", location: "Bletchley", status: "Away" }
           ] %>
           <%= tabler_ui.table columns: mobile_columns, data: mobile_rows, mobile: true %>
         ERB

  c.demo :sort_filter_page,
         title: "frame: (Turbo Frame: sorting, filtering and paging without a page reload; pager in footer:; search button: \"Search\"; filter min_chars: 3)",
         locals: -> {
           default_params = {}
           {
             table_demo_rows: TablerUi::Docs::TableDemoController.table_demo_rows(default_params),
             table_demo_sort: TablerUi::Docs::TableDemoController.table_demo_sort(default_params),
             table_demo_page: TablerUi::Docs::TableDemoController.table_demo_page(default_params),
             table_demo_total_pages: TablerUi::Docs::TableDemoController.table_demo_total_pages(default_params),
             table_demo_sort_url: TablerUi::Docs::TableDemoController.table_demo_sort_url(default_params),
             table_demo_pagination_url: TablerUi::Docs::TableDemoController.table_demo_pagination_url(default_params),
             table_demo_filter_url: TablerUi::Docs::TableDemoController.table_demo_filter_url,
             table_demo_reset_url: TablerUi::Docs::TableDemoController.table_demo_reset_url(default_params)
           }
         },
         source: <<~'ERB'
           <% table_demo_columns = [
             { label: "Name", sort: "name", value: ->(row) { row[:name] } },
             { label: "Status", sort: "status",
               value: ->(row) { tabler_ui.status(text: row[:status].capitalize,
                                                  color: { "active" => "success", "away" => "warning" }.fetch(row[:status], "secondary"),
                                                  dot: true) } },
             { label: "Created", sort: "created_at", value: ->(row) { row[:created_at].strftime("%b %-d, %Y") } },
             { label: "Actions", value: ->(row) { link_to "View", "#" } }
           ] %>
           <%= tabler_ui.table columns: table_demo_columns, data: table_demo_rows, hover: true,
                               sort: table_demo_sort,
                               sort_url: table_demo_sort_url,
                               sort_reset: true,
                               frame: "table-demo",
                               filter: {
                                 url: table_demo_filter_url,
                                 hidden: { sort: table_demo_sort[:key], dir: table_demo_sort[:dir] },
                                 min_chars: 3,
                                 fields: [
                                   { name: "q", value: nil, button: "Search" },
                                   { name: "status", type: :select, label: "Status", value: nil,
                                     include_blank: true, options: %w[active away inactive] }
                                 ],
                                 reset: table_demo_reset_url
                               } do |slots| %>
             <% slots.footer do %>
               <%= tabler_ui.pagination current: table_demo_page, total: table_demo_total_pages,
                                        url: table_demo_pagination_url %>
             <% end %>
           <% end %>
         ERB

  c.demo :filter_no_frame,
         title: "filter min_chars: 3, no frame: (no effect: needs auto-submit + frame: together, so this uses a manual Search button)",
         source: <<~'ERB'
           <% inert_columns = [
             { label: "Name", value: ->(row) { row[:name] } },
             { label: "Status", value: ->(row) { row[:status].capitalize } }
           ] %>
           <% inert_rows = [
             { name: "Ada Lovelace", status: "active" },
             { name: "Grace Hopper", status: "active" },
             { name: "Alan Turing", status: "away" }
           ] %>
           <%= tabler_ui.table columns: inert_columns, data: inert_rows, hover: true,
                               filter: {
                                 url: "#",
                                 auto: false,
                                 min_chars: 3,
                                 fields: [
                                   { name: "inert_q", value: nil, button: "Search" }
                                 ]
                               } %>
         ERB
end
