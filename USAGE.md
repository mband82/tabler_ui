# tabler_ui usage

> **Generated file.** Do not hand-edit -- run `rake tabler_ui:usage_doc`
> after changing a component's doc comments or a file under
> `docs/lib/tabler_ui/docs/demos/`. Source of truth: each component's
> own doc comments (parsed by `TablerUi::Docs::DocParser`) and its
> registered demos (`TablerUi::Docs::DemoRegistry`).

## 1. Install

```ruby
gem "tabler_ui", git: "https://github.com/webbastelbude/tabler_ui.git"
```

Pulls in `rails` (>= 7.0), `stimulus-rails`, `ostruct` and
`sprockets-rails` (~> 3.5) -- the last one is required even on a
Propshaft host; the next section explains why.

## 2. Asset setup

`app/assets/stylesheets/tabler_ui.css` is a **Sprockets directive
manifest** -- six `*= require` lines, no CSS of its own. Propshaft has
no directive processor, so a Propshaft host is served that file's
comments byte-for-byte: no error, no styling, nothing to point at in
the console. Pick whichever matches the host app.

**Sprockets** -- add to `app/assets/stylesheets/application.css`:

```
/*
 *= require tabler_ui
 */
```

**Propshaft (Rails 8 default)** -- link the pre-built, directive-free
bundle instead:

```erb
<%= stylesheet_link_tag "tabler_ui_all" %>
```

## 3. JavaScript

The gem's own `config/importmap.rb` is auto-loaded by the engine, so
`tabler_ui` and its Stimulus controllers are already pinned. What
still matters is order: `tabler_ui.js` registers its controllers
inside `if (window.Stimulus)`, so the host must start Stimulus and
assign `window.Stimulus` **before** importing `"tabler_ui"`.

```js
// app/javascript/controllers/application.js
import { Application } from "@hotwired/stimulus"
const application = Application.start()
window.Stimulus = application
export { application }
```

```js
// app/javascript/application.js
import "controllers/application"
import "tabler_ui"
```

## 4. Mount the docs engine

Optional: mount `TablerUi::Docs::Engine` anywhere and every component
gets a generated reference page plus its live demos.

```ruby
mount TablerUi::Docs::Engine, at: "/ui"
```

## HTML attributes

Most components take a hash of HTML attributes for one or more of the
elements they render. You supply the hash, the component merges it
onto its own defaults, and the result becomes that element's
attributes. Every component section below names its own `html:`
keys; this section is the one place the merge itself is explained.

### The naming convention

`html:` targets a component's root element. A part-specific hook is
named `<part>_html:`. Card renders three named parts, each with its
own hook:

```ruby
tabler_ui.card title: "Invoices",
              header_html: { class: "bg-dark" },
              body_html:   { class: "p-0" },
              footer_html: { class: "text-end" } do |slots|
  ...
end
```

### The merge rule

What happens depends on the attribute name, decided by
`TablerUi::HtmlOptions.merge_html`:

| Attribute | Rule |
| --- | --- |
| `class` | Appended to the component's own classes, deduplicated. Never replaces them. |
| `data` | Merged one level deep -- your keys and the component's own keys both survive; a key given by both sides, yours wins. |
| `aria` | Same rule as `data` -- merged one level deep. |
| anything else | Yours overwrites the component's outright. |

A worked example -- Button's `confirm:` option already puts a
`turbo_confirm` key into the root element's `:data`. Adding your own
`data:` via `html:` does not replace it:

```ruby
tabler_ui.button text: "Delete", color: "danger", confirm: "Are you sure?",
                 html: { data: { testid: "delete-button" } }

# component's own defaults for the root element:
{ class: "btn btn-danger", data: { turbo_confirm: "Are you sure?" } }

# your html: option:
{ data: { testid: "delete-button" } }

# merged -- both data keys survive, class is untouched by data at all:
{ class: "btn btn-danger", data: { turbo_confirm: "Are you sure?", testid: "delete-button" } }
```

### Per-item hooks: callables

Parts that repeat -- table rows, pagination links, breadcrumb items --
also accept a **proc** instead of a Hash. It is called once per item
and receives that item; whatever Hash it returns is merged exactly
like a static one. A proc returning `{}` or `nil` contributes
nothing. Table's `row_html:`:

```ruby
tabler_ui.table columns: columns, data: invoices,
               row_html: ->(row) { row.overdue? ? { class: "table-danger" } : {} }
```

On the component side, that hook is resolved with
`html_for(:row, {}, row)` -- the extra argument after the defaults
hash is what the stored proc gets called with.

### When the element doesn't render

A hook only applies to an element the component actually renders.
Breadcrumb's `link_html:` targets each item's `<a>` -- but the
current item, and any item with no `url:`, renders as plain text with
no `<a>` to apply it to. `link_html:` is silently skipped for that
item; use the item's own `html:` (part `:item`, its `<li>`) to reach
it instead.

## Authorization

Every component and subcomponent accepts an `auth:` option. Configure
the check once, globally -- it defaults to always-true, so nothing
changes for a host that never calls it:

```ruby
tabler_ui.set_auth_method { |permission| current_user.can?(permission) }
```

The configured method is invoked on every `tabler_ui.*` call, whether
or not `auth:` was passed explicitly (an omitted `auth:` is just `nil`
as the argument). A falsy return means that component is not rendered
at all, and its block never runs:

```ruby
tabler_ui.card title: "Admin settings", auth: :manage_settings do |slots|
  slots.body { "Only rendered when the auth_method authorizes :manage_settings" }
end
```

A subcomponent that doesn't set its own `auth:` inherits its parent
component's `auth:` value as the default (not `nil`) -- this is being
built out per-subcomponent in a later wave, so as of this writing only
top-level components are gated.

This is unrelated to Navbar's own pre-existing `action:`/`subject:` +
`can?` check -- a separate, older, Navbar-only mechanism; both apply
independently.

## Design editor

Mounting `TablerUi::Docs::Engine` (see Install, step 4) also mounts an
in-browser visual editor at `GET <mount>/editor`. It is a way to
compose a real Rails view out of `tabler_ui.*` components by dragging
and clicking, with a live preview, without writing ERB by hand.

A design is a Rails-shaped tree -- rows/columns, headings/text, and
`tabler_ui.*` components with their own options, HTML hooks and (for
builder-style components) sub-items -- built up on a canvas via
drag-and-drop or plain move-up/move-down/delete buttons, with in-canvas
text editing and a property panel driven by each component's own
documented options. A workspace can hold several files and directories;
one file can reference another as a partial.

**Where a design lives.** Nowhere on the server. The whole workspace
(every file's tree) is kept in the browser's own `localStorage` --
nothing is persisted server-side, and nothing survives clearing that
browser's site data. The server sees a design only for the length of
one preview request.

**What comes out.** Copy or download any file's generated `.html.erb`,
or export the whole workspace as a zip, and paste the result into a
real Rails app. That generated ERB is exactly what a developer would
have written by hand -- `<%= tabler_ui.card title: "Invoices" do |slots| %>`
and so on -- not a runtime dependency on the editor or on anything
under `docs/`.

**How the preview is produced.** The posted design tree is validated
and normalized, then walked twice by independent code paths that must
produce equivalent output: one renders it to real HTML by calling the
same `tabler_ui.*` dispatcher a hand-written view would, for the live
preview; the other renders it to the same `.html.erb` text offered for
export. Neither path ever turns the posted data into an ERB source
string and evaluates it -- a design is data, walked and dispatched,
never template source.

**Real limits, not just a demo.** A component option that only Ruby can
express -- a `Proc`, an opaque object -- cannot be set from the editor;
the property panel reports it as unsupported. The one exception is a
table's `:columns`, where the editor takes a declarative column `key:`
and the value-lookup callable is synthesized from it, on both the
preview and export paths. A few structured options with no scalar UI
equivalent (a datagrid's `:items`, a rating's `:choices`, ...) fall
back to a raw-JSON field in the property panel rather than a purpose-built
control.

## Components

### Layout

#### Accordion -- tabler_ui.accordion

Accordion component for Tabler UI. Renders a `.accordion` of stacked
`.accordion-item`s, each with a clickable `.accordion-header` and a
`.accordion-collapse` pane driven by Bootstrap's Collapse (via
`tabler-ui--collapse`, the same lifecycle controller the navbar's
collapsible nav already uses -- see collapse_controller.js). Builder
style: the block yields the component itself, and items are added via
#item.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `flush` | Boolean | Removes the default borders/rounded corners (.accordion-flush) |
| `inverted` | Boolean | Moves the toggle icon before the title (.accordion-inverted) |
| `style` | Symbol | :tabs for the card-like accordion-tabs variant (default: plain) |
| `toggle_style` | Symbol | Toggle icon: :chevron (default) or :plus |
| `multiple` | Boolean | Allow more than one item open at once (default: false -- single-open, each pane closes its siblings via data-bs-parent) |
| `html` | Hash | HTML attributes for the outer wrapper (part :root) |

**Examples**

**Basic usage with block -- single-open by default**

```ruby
<%= tabler_ui.accordion("my-accordion") do |accordion| %>
  <% accordion.item("First item", open: true) do %>
    Content for the first item
  <% end %>
  <% accordion.item("Second item") do %>
    Content for the second item
  <% end %>
<% end %>
```

**Multiple items open at once**

```ruby
<%= tabler_ui.accordion("my-accordion", multiple: true) do |accordion| %>
  <% accordion.item("First", open: true) { "Content" } %>
  <% accordion.item("Second", open: true) { "Content" } %>
<% end %>
```

**flush / inverted / accordion-tabs / plus toggle**

```ruby
<%= tabler_ui.accordion("my-accordion", flush: true, inverted: true,
                        style: :tabs, toggle_style: :plus) do |accordion| %>
  ...
<% end %>
```

**HTML attributes -- component-level and per-item**

```ruby
<%= tabler_ui.accordion("my-accordion", html: { class: "mb-3" }) do |accordion| %>
  <% accordion.item("First", icon: "home",
                     html: { class: "fw-bold" },
                     header_html: { class: "bg-light" },
                     body_html: { class: "p-2" }) { "Content" } %>
<% end %>
```

**Demos**

**flush, toggle_style: :plus**

```erb
<%= tabler_ui.accordion("demo-accordion", flush: true, toggle_style: :plus) do |acc| %>
  <% acc.item("What is Tabler UI?", open: true, icon: "info-circle") do %>
    A Rails component library on top of the Tabler.io design system.
  <% end %>
  <% acc.item("Is it free?") do %>
    Yes, MIT licensed.
  <% end %>
  <% acc.item("Does it need a database?") do %>
    No -- every component is a stateless view helper.
  <% end %>
<% end %>
```

#### Card -- tabler_ui.card

Card component for Tabler UI. Renders a `.card` wrapper with optional
`.card-header`, `.card-body`, `.card-footer` parts, filled in via slots
(or a plain `title:` for a simple header).

The block yields a single argument, the `SlotContext` -- `do |slots|`, not `do |card, slots|`.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `title` | String | Rendered as an `<h3 class="card-title">` inside the header when no `header` slot is given. |
| `size` | String, Symbol | Card size -- card-<size> (e.g. "sm", "lg") |
| `status` | String | Colour for a status strip child div -- validated against TablerUi::Color. No strip is rendered without it. |
| `status_position` | String | Where the strip sits -- "top" (default), "start" or "bottom". Has no effect without `status:`. |
| `borderless` | Boolean | card-borderless (default: false) |
| `stacked` | Boolean | card-stacked (default: false) |
| `html` | Hash | HTML attributes for the outer `.card` (part :root) |
| `header_html` | Hash | HTML attributes for the `.card-header` (part :header) |
| `body_html` | Hash | HTML attributes for the `.card-body` (part :body) |
| `footer_html` | Hash | HTML attributes for the `.card-footer` (part :footer) |
| `status_html` | Hash | HTML attributes for the status strip (part :status) |

**Examples**

**Basic usage -- title plus a body slot**

```ruby
<%= tabler_ui.card title: "Card title" do |slots| %>
  <% slots.body do %>Card content<% end %>
<% end %>
```

**Custom header content overrides title:**

```ruby
<%= tabler_ui.card title: "Ignored" do |slots| %>
  <% slots.header do %><h3>Custom header</h3><% end %>
<% end %>
```

**Footer slot**

```ruby
<%= tabler_ui.card do |slots| %>
  <% slots.body do %>Content<% end %>
  <% slots.footer do %>Last updated 3 min ago<% end %>
<% end %>
```

**Status strip, borderless, stacked, size**

```ruby
<%= tabler_ui.card title: "x", status: "red", borderless: true,
                    stacked: true, size: "lg" %>
```

**HTML attributes**

```ruby
<%= tabler_ui.card title: "x", html: { class: "mb-4" },
                    header_html: { class: "bg-dark" },
                    body_html: { class: "p-0" },
                    footer_html: { class: "text-end" } do |slots| %>
  <% slots.body do %>Content<% end %>
<% end %>
```

**Demos**

**title + body + footer**

```erb
<%= tabler_ui.card title: "Card title" do |slots| %>
  <% slots.body { "Card body content." } %>
  <% slots.footer { "Updated 3 min ago" } %>
<% end %>
```

**status strip, borderless, stacked**

```erb
<%= tabler_ui.card title: "Server status", status: "danger", stacked: true do |slots| %>
  <% slots.body { "3 servers are unreachable." } %>
<% end %>
```

**status_position: "top" (default)**

```erb
<%= tabler_ui.card title: "Top strip", status: "danger", status_position: "top" do |slots| %>
  <% slots.body { "Status strip along the top edge." } %>
<% end %>
```

**status_position: "start"**

```erb
<%= tabler_ui.card title: "Start strip", status: "azure", status_position: "start" do |slots| %>
  <% slots.body { "Status strip along the leading edge." } %>
<% end %>
```

**status_position: "bottom"**

```erb
<%= tabler_ui.card title: "Bottom strip", status: "success", status_position: "bottom" do |slots| %>
  <% slots.body { "Status strip along the bottom edge." } %>
<% end %>
```

#### Card group -- tabler_ui.card_group

CardGroup component for Tabler UI. Renders a `.card-group` wrapper
meant to hold several `tabler_ui.card` calls, filled in via a `body`
slot.

Verified CSS contract (see .card-group rules in tabler.css): the cards
must be *direct children* of `.card-group` -- `.card-group > .card`
uses a direct-child combinator, and the corner-rounding rules key off
`:not(:first-child)` / `:not(:last-child)` on that same direct-child
relationship. Do not wrap the cards in an intermediate `<div>` inside
the body slot, or the flex layout and rounded-corner rules silently
stop applying. DOM order matters too -- first/last child determine
which corners stay rounded.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `html` | Hash | HTML attributes for the outer `.card-group` (part :root) |

**Examples**

```ruby
<%= tabler_ui.card_group do |slots| %>
  <% slots.body do %>
    <%= tabler_ui.card title: "One" do |card_slots| %>
      <% card_slots.body { "First" } %>
    <% end %>
    <%= tabler_ui.card title: "Two" do |card_slots| %>
      <% card_slots.body { "Second" } %>
    <% end %>
  <% end %>
<% end %>
```

**HTML attribute**

```ruby
<%= tabler_ui.card_group html: { class: "mb-4" } do |slots| %>
  <% slots.body do %>...<% end %>
<% end %>
```

**Demos**

**cards as direct children (not wrapped in a column/div)**

```erb
<%= tabler_ui.card_group do |slots| %>
  <% slots.body do %>
    <%= tabler_ui.card title: "One" do |c| %>
      <% c.body { "First card in the group." } %>
    <% end %>
    <%= tabler_ui.card title: "Two" do |c| %>
      <% c.body { "Second card in the group." } %>
    <% end %>
    <%= tabler_ui.card title: "Three" do |c| %>
      <% c.body { "Third card in the group." } %>
    <% end %>
  <% end %>
<% end %>
```

#### Datagrid -- tabler_ui.datagrid

Datagrid component for Tabler UI. Renders a `.datagrid` of label/value
pairs, each a `.datagrid-item` with a `.datagrid-title` and
`.datagrid-content`. Builder-style: the block yields the component
itself, and items are added via `#item`.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `items` | Array<Hash> | Pre-built items, each a Hash with `:title` and `:content` (default: []) |
| `html` | Hash | HTML attributes for the outer `.datagrid` (part :root) |
| `item_html` | Hash, Proc | HTML attributes for each `.datagrid-item` (part :item). Either a plain Hash (applied to every item) or a callable taking the item and returning a Hash. |
| `title_html` | Hash, Proc | HTML attributes for each `.datagrid-title` (part :title) |
| `content_html` | Hash, Proc | HTML attributes for each `.datagrid-content` (part :content) |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.datagrid do |dg| %>
  <% dg.item "Name", content: "Ada Lovelace" %>
  <% dg.item "Bio" do %>
    <strong>Mathematician</strong>
  <% end %>
<% end %>
```

**items: passed directly at construction**

```ruby
<%= tabler_ui.datagrid items: [{ title: "Name", content: "Ada" }] %>
```

**HTML attributes**

```ruby
<%= tabler_ui.datagrid html: { class: "mb-4" },
                       item_html: ->(item) { item[:title] == "Name" ? { class: "fw-bold" } : {} },
                       title_html: { class: "text-muted" },
                       content_html: { class: "text-end" } do |dg| %>
  <% dg.item "Name", content: "Ada" %>
<% end %>
```

**Demos**

**content: and a block item**

```erb
<%= tabler_ui.datagrid do |dg| %>
  <% dg.item "Full name", content: "Ada Lovelace" %>
  <% dg.item "Email", content: "ada@example.com" %>
  <% dg.item "Bio" do %>
    <strong>Mathematician</strong> and writer.
  <% end %>
<% end %>
```

#### Navbar -- tabler_ui.navbar

Renders a responsive `header.navbar` with left/right nav-item groups
(links, dropdown submenus, a divider, or the dark mode toggle) and a
mobile collapse toggler. Builder-style: the block yields the component
itself; add items through `left`/`right`'s `add` and `dropdown`.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `brand` | String | Brand/logo markup, rendered as-is inside `.navbar-brand` |
| `brand_autodark` | Boolean | Adds `navbar-brand-autodark` to the brand element (default: true) |
| `expand` | String, Symbol | Breakpoint at/above which the navbar shows its full menu; below it, collapses behind the toggler. One of `sm`/`md`/`lg`/`xl`/`xxl` (default: `lg`). Invalid values raise `ArgumentError`. |
| `dark` | Boolean | Adds `navbar-dark` (switches text/brand/toggler-icon colours for a dark background). Sets no background itself -- pair with a `bg-*` utility. |
| `transparent` | Boolean | Adds `navbar-transparent` (transparent background and border). |
| `overlap` | Boolean | Adds `navbar-overlap`, extending the navbar's background 9rem below it. |
| `nav_scroll` | Boolean | Adds `navbar-nav-scroll` to the collapsible menu, capping it at `var(--tblr-scroll-height, 75vh)` with a scrollbar. Only takes effect while collapsed. Set a custom cap via `menu_html: { style: "--tblr-scroll-height: 300px" }`. |
| `html` | Hash | HTML attributes for the outer `header.navbar` (part :root) |
| `brand_html` | Hash | HTML attributes for `.navbar-brand` (part :brand) |
| `toggler_html` | Hash | HTML attributes for the mobile toggler button (part :toggler) |
| `menu_html` | Hash | HTML attributes for the collapsible menu container (part :menu) |
| `link_html` | Hash, #call | HTML attributes applied to every plain nav link's `<a>` (or the `<button>` inside `button_to`'s `<form>` for a non-GET `method:`) -- part :link. A Hash, or a callable taking the item. Merged underneath this item's own `link_html:` given to `NavigationGroup#add`. Does *not* reach the dropdown toggle (`dropdown_toggle_html:`) or dropdown sub-item links (their own per-item `link_html:` on `DropDownProxy#item`). |
| `dropdown_toggle_html` | Hash, #call | HTML attributes applied to every dropdown's toggle `<a class="dropdown-toggle">` (part :dropdown_toggle) -- a Hash, or a callable taking the item. A caller's own `data:` deep-merges with the toggle's built-in `data-bs-toggle`/`data-controller` rather than replacing them. |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.navbar(brand: link_to("MyApp", root_path)) do |navbar| %>
  <% navbar.left do |nav| %>
    <% nav.add "Home", url: root_path %>
    <% nav.add "About", url: about_path %>
  <% end %>
<% end %>
```

**Nested dropdown**

```ruby
<%= tabler_ui.navbar do |navbar| %>
  <% navbar.left do |nav| %>
    <% nav.dropdown "Admin", align: :end do |dd| %>
      <% dd.header "Manage" %>
      <% dd.item "Users", url: admin_users_path %>
      <% dd.divider %>
      <% dd.item "Settings", url: admin_settings_path, icon: "settings" %>
    <% end %>
  <% end %>
<% end %>
```

**HTML attributes -- component-level and per nav-item**

```ruby
<%= tabler_ui.navbar(html: { class: "shadow-sm" },
                     brand_html: { class: "fw-bold" },
                     toggler_html: { class: "border-0" },
                     menu_html: { class: "gap-2" }) do |navbar| %>
  <% navbar.left do |nav| %>
    <% nav.add "Home", url: root_path, html: { class: "text-danger" } %>
  <% end %>
<% end %>
```

**HTML attributes -- the nav link and dropdown toggle `<a>`s themselves**

```ruby
<%= tabler_ui.navbar(link_html: { data: { testid: "nav-link" } },
                     dropdown_toggle_html: { class: "fw-bold" }) do |navbar| %>
  <% navbar.left do |nav| %>
    <% nav.add "Home", url: root_path, link_html: { class: "text-danger" } %>
    <% nav.dropdown "Admin" do |dd| %>
      <% dd.item "Users", url: admin_users_path, link_html: { class: "fw-bold" } %>
    <% end %>
  <% end %>
<% end %>
```

**Demos**

**left/right nav items, dropdown, dark mode toggle**

```erb
<%= tabler_ui.navbar(brand: link_to("MyApp", "#"),
                      menu_html: { id: "navbar-basics-menu" },
                      toggler_html: { "data-bs-target": "#navbar-basics-menu", "aria-controls": "navbar-basics-menu" }) do |navbar| %>
  <% navbar.left do |nav| %>
    <% nav.add "Home", url: "#", active: true %>
    <% nav.add "Reports", url: "#", active: false %>
    <% nav.dropdown "Admin", align: :end do |dd| %>
      <% dd.header "Manage" %>
      <% dd.item "Users", url: "#", icon: "users", active: false %>
      <% dd.divider %>
      <% dd.item "Settings", url: "#", icon: "settings", active: false %>
    <% end %>
  <% end %>
  <% navbar.right do |nav| %>
    <% nav.dark_mode_toggle %>
  <% end %>
<% end %>
```

**expand: "sm" (collapses above sm, instead of the lg default)**

```erb
<%= tabler_ui.navbar(brand: link_to("MyApp", "#"), expand: "sm",
                      menu_html: { id: "navbar-expand-sm-menu" },
                      toggler_html: { "data-bs-target": "#navbar-expand-sm-menu", "aria-controls": "navbar-expand-sm-menu" }) do |navbar| %>
  <% navbar.left do |nav| %>
    <% nav.add "Home", url: "#", active: true %>
    <% nav.add "Reports", url: "#", active: false %>
  <% end %>
<% end %>
```

**dark: true (text/icons only -- paired with bg-primary via html:)**

```erb
<%= tabler_ui.navbar(brand: link_to("MyApp", "#"), dark: true, html: { class: "bg-primary" },
                      menu_html: { id: "navbar-dark-menu" },
                      toggler_html: { "data-bs-target": "#navbar-dark-menu", "aria-controls": "navbar-dark-menu" }) do |navbar| %>
  <% navbar.left do |nav| %>
    <% nav.add "Home", url: "#", active: true %>
    <% nav.add "Reports", url: "#", active: false %>
  <% end %>
<% end %>
```

**transparent: true**

```erb
<div class="bg-blue-lt p-3">
  <%= tabler_ui.navbar(brand: link_to("MyApp", "#"), transparent: true,
                        menu_html: { id: "navbar-transparent-menu" },
                        toggler_html: { "data-bs-target": "#navbar-transparent-menu", "aria-controls": "navbar-transparent-menu" }) do |navbar| %>
    <% navbar.left do |nav| %>
      <% nav.add "Home", url: "#", active: true %>
      <% nav.add "Reports", url: "#", active: false %>
    <% end %>
  <% end %>
</div>
```

**overlap: true (background extends 9rem below it; content sits on top)**

```erb
<%= tabler_ui.navbar(brand: link_to("MyApp", "#"), overlap: true,
                      menu_html: { id: "navbar-overlap-menu" },
                      toggler_html: { "data-bs-target": "#navbar-overlap-menu", "aria-controls": "navbar-overlap-menu" }) do |navbar| %>
  <% navbar.left do |nav| %>
    <% nav.add "Home", url: "#", active: true %>
  <% end %>
<% end %>
<div class="container-xl mt-n5">
  <div class="card">
    <div class="card-body">This card overlaps the navbar's extended background.</div>
  </div>
</div>
```

**nav_scroll: true, menu_html: custom --tblr-scroll-height (collapse below lg to see it scroll)**

```erb
<%= tabler_ui.navbar(brand: link_to("MyApp", "#"), nav_scroll: true,
                      menu_html: { id: "navbar-nav-scroll-menu", style: "--tblr-scroll-height: 300px" },
                      toggler_html: { "data-bs-target": "#navbar-nav-scroll-menu", "aria-controls": "navbar-nav-scroll-menu" }) do |navbar| %>
  <% navbar.left do |nav| %>
    <% (1..10).each do |n| %>
      <% nav.add "Item #{n}", url: "#", active: false %>
    <% end %>
  <% end %>
<% end %>
```

#### Page header -- tabler_ui.page_header

Page header component for Tabler UI. Renders the `.page-header` block
used atop a page: an optional `.page-pretitle`, the `h2.page-title`,
and a right-aligned `buttons` slot for page-level actions.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `title` | String | Page title, rendered in an `h2.page-title` (part :title) |
| `pretitle` | String | Small label above the title (part :pretitle), only when present. Distinct from :subtitle. |
| `subtitle` | String | Small label below the title (part :subtitle), only when present. Can be combined with :pretitle. |
| `border` | Boolean | Appends `page-header-border` to the root element (part :root) when true. |
| `title_size` | String | "lg" adds `page-title-lg` (part :title). Any other value raises ArgumentError. |
| `html` | Hash | HTML attributes for the outermost `.page-header` element (part :root) |
| `title_html` | Hash | HTML attributes for the `h2.page-title` (part :title) |
| `pretitle_html` | Hash | HTML attributes for the `.page-pretitle` div (part :pretitle), only used when a pretitle renders |
| `subtitle_html` | Hash | HTML attributes for the `.page-subtitle` div (part :subtitle), only used when a subtitle renders |
| `buttons_html` | Hash | HTML attributes for the right-aligned buttons column (part :buttons), only used when the `buttons` slot has content |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.page_header title: "Dashboard" %>
```

**With a pretitle**

```ruby
<%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview" %>
```

**No mandatory argument at all**

```ruby
<%= tabler_ui.page_header %>
```

**With a buttons slot -- the block receives a single SlotContext**

```ruby
<%= tabler_ui.page_header title: "Dashboard" do |slots| %>
  <% slots.buttons do %>
    <%= tabler_ui.button text: "New report", color: "primary" %>
  <% end %>
<% end %>
```

**HTML attributes**

```ruby
<%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview",
                          html: { class: "mb-4" },
                          title_html: { class: "text-uppercase" },
                          pretitle_html: { data: { testid: "pretitle" } },
                          buttons_html: { class: "gap-2" } %>
```

**Border, large title and a subtitle**

```ruby
<%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview",
                          subtitle: "Last 30 days", border: true,
                          title_size: "lg" %>
```

**Demos**

**title, pretitle, buttons slot**

```erb
<%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview" do |slots| %>
  <% slots.buttons do %>
    <%= tabler_ui.button text: "New report", color: "primary", icon: "plus" %>
  <% end %>
<% end %>
```

**border: true**

```erb
<%= tabler_ui.page_header title: "Dashboard", border: true %>
```

**title_size: "lg"**

```erb
<%= tabler_ui.page_header title: "Dashboard", title_size: "lg" %>
```

**pretitle: (above title) + subtitle: (below title)**

```erb
<%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview", subtitle: "Last 30 days" %>
```

#### Settings page -- tabler_ui.settings_page

SettingsPage component for Tabler UI. Renders a `.card` with a sidebar
list-group of items on the left and a matching tab-pane per item on the
right. Builder-style: the block yields the component itself, and items
are added via #item.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `title` | String | Displayed above the sidebar navigation (default: "Settings") |
| `html` | Hash | HTML attributes for the outer `.card` (part :root) |
| `sidebar_html` | Hash | HTML attributes for the sidebar column/card-body (part :sidebar) |
| `content_html` | Hash | HTML attributes for the content area (part :content) |

**Examples**

**Basic usage with block**

```ruby
<%= tabler_ui.settings_page("my-settings", title: "Settings") do |sp| %>
  <% sp.item("General", icon: "settings") do %>
    Content for general settings
  <% end %>
  <% sp.item("Security", icon: "shield", active: true) do %>
    Content for security settings
  <% end %>
<% end %>
```

**HTML attributes -- component-level and per-item**

```ruby
<%= tabler_ui.settings_page("my-settings",
                             html: { class: "mb-4" },
                             sidebar_html: { class: "bg-dark" },
                             content_html: { class: "p-0" }) do |sp| %>
  <% sp.item("General", html: { class: "fw-bold" }) do %>Content<% end %>
  <% sp.item("Security", html: ->(item) { { class: "text-danger" if item.title == "Security" } }) do %>
    Content
  <% end %>
<% end %>
```

**Demos**

**item blocks with icons**

```erb
<%= tabler_ui.settings_page("demo-settings", title: "Settings") do |sp| %>
  <% sp.item("General", icon: "settings") do %>
    General settings content.
  <% end %>
  <% sp.item("Security", icon: "shield-check") do %>
    Security settings content.
  <% end %>
  <% sp.item("Notifications", icon: "bell") do %>
    Notification settings content.
  <% end %>
<% end %>
```

#### Table -- tabler_ui.table

Table component for Tabler UI. Renders a `.card > .table-responsive >
table` wrapper (card optional) around a `<thead>` built from `columns:`
and a `<tbody>` built by invoking each column's `:value` callable
against every row in `data:`.

Also wires up sortable column headers and a filter/search toolbar,
without touching an ORM, `params`, or a query -- you supply the
current state (sorted column/direction, current filter values) and a
URL builder, and this component only renders links and a form.

##### Sorting

Give a column a `:sort` key to make it sortable. Its `<th>` renders
as `<a class="table-sort">`, linking to `sort_url.call(key, dir)`
where `dir` is whichever direction that click would apply next:

* unsorted -> :asc
* sorted :asc -> :desc
* sorted :desc -> :asc, or with `sort_reset: true` -> nil (unsorted)

The active column's `<th>` carries `aria-sort`; its `<a>` carries a
matching `asc`/`desc` class. Other columns are unaffected.

##### Filtering

`filter:` renders a search toolbar via `fields:` (an array of field
hashes) or a `slots.filter { ... }` block -- mutually exclusive,
raises ArgumentError if both are given.
* `:url`, `:method` (:get/:post, default :get)
* `:auto` -- self-submits on input/change; true only for a :get
  form with `frame:` set. Without `frame:`, auto-submitting makes
  every keystroke a full navigation -- the input loses focus, the
  page jumps to the top.
* `:min_chars` -- positive Integer, needs a :search/:text field.
  Active only when BOTH `auto:` and `frame:` are set (deliberate,
  not a bug); below threshold the field submits blank.
* `:hidden`, `:reset`, `:submit`, `:debounce` -- hidden fields,
  Reset link, Apply label (hidden when `auto:` true), Stimulus
  debounce (ms).
Field hashes: `:name` (mandatory), `:type` (:search default/:text/
:select/:date), `:value`, `:label`, `:placeholder`, `:options`,
`:col`, `:html`, `:id`, `:button` (search/text only).

##### Footer

`slots.footer { ... }` renders a `.card-footer` (or `mt-3` when
`card: false`) after the table -- typically a pager, a row count, a
"Showing 1-10 of 50" summary. No `footer:` options hash; it's a slot
only, on/off by whether the block set it.

Unlike the filter toolbar, the footer renders *inside* `frame:` --
see "Turbo Frames" below.

##### Turbo Frames

`frame:` wraps the table and the footer slot (if any) in a single
`<turbo-frame>`, so sorting, filtering, and a footer pager all
navigate inside it instead of reloading the page. Plain markup --
no turbo-rails dependency, inert without Turbo's JS.

* `:id` -- mandatory, raises ArgumentError if blank/missing.
* `:advance` -- `data-turbo-action="advance"` when true (default),
  so the URL bar and back button follow along; false omits it.
* `:src`, `:loading` (:lazy/:eager) -- lazily-loaded table: ships
  empty, Turbo fetches `src:` once it scrolls into view.

###### Footer in, filter out

The footer slot sits *inside* the frame (it reflects table state --
a pager needs to swap with the rows, or its highlight goes stale).
The filter form stays *outside* the frame and targets it via
`data-turbo-frame="<id>"` instead -- if the toolbar sat inside the
frame, a response landing mid-typing would replace the search input
and destroy its focus/caret. Sortable header links already live
inside the frame, so they need no explicit targeting.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `columns` | Array<Hash> | Each hash carries a `:label`, an optional `:class` (appended to the cell's own class, never replacing it), an optional `:sort` sort key (see "Sorting" below), and a `:value` callable invoked as `value.call(row)` per row. |
| `data` | Enumerable | The row collection (default: []) |
| `striped` | Boolean | table-striped (default: false) |
| `hover` | Boolean | table-hover (default: false) |
| `bordered` | Boolean | table-bordered (default: false) |
| `sm` | Boolean | table-sm (default: false) |
| `nowrap` | Boolean | table-nowrap (default: false) |
| `vcenter` | Boolean | table-vcenter (default: false) |
| `card` | Boolean | Wrap the table in a `.card` / `.table-responsive` shell (default: true). Set to false to nest the table inside an existing card without double-wrapping. Also affects the filter toolbar's own shell -- see "Filtering" below. |
| `responsive` | Boolean, String | Controls the horizontal- scroll wrapper. `true` (default) emits `table-responsive` (scrolls at every width). A breakpoint string ("sm"/"md"/"lg"/"xl"/"xxl") emits `table-responsive-<bp>` instead (scrolls only below that breakpoint). `false` emits neither class. |
| `mobile` | Boolean, String | Stacks the table into a card-like list below a breakpoint via `table-mobile` (`true`, all widths) or `table-mobile-<bp>` (a breakpoint string). Adds a `data-label` attribute (the column's `:label`) to every `<td>`, which the CSS reads to draw the heading in the stacked layout. |
| `sort` | Hash | Current sort state, `{ key:, dir: }`. `dir:` accepts :asc/:desc (or their string forms) and defaults to :asc when `key:` is given without it; an unrecognised `dir:` raises ArgumentError. nil/absent (the default) means unsorted. See "Sorting" below. |
| `sort_url` | #call | Sorting only -- a callable invoked as `sort_url.call(key, dir)` returning the href for a sortable column's header link. Mandatory (raises ArgumentError at initialize time) as soon as any column carries `sort:`. |
| `sort_reset` | Boolean | When true, clicking a column that is currently sorted :desc cycles to unsorted (`sort_url.call(key, nil)`) instead of back to :asc (default: false). See "Sorting" below. |
| `filter` | Hash | Turns on the filter/search toolbar -- see "Filtering" below. Absent (the default) renders nothing extra at all; the rest of the table's output is unaffected. |
| `frame` | String, Hash | Opt-in Turbo Frame support -- see "Turbo Frames" below. A String is shorthand for `{ id: the String }`. Absent (the default) renders no `<turbo-frame>` at all; the rest of the table's output is unaffected. |
| `html` | Hash | HTML attributes for the outermost element -- the `.card` wrapper, or the `.table-responsive` div when `card: false` (part :root) |
| `table_html` | Hash | HTML attributes for the `<table>` (part :table) |
| `thead_html` | Hash | HTML attributes for the `<thead>` (part :thead) |
| `tbody_html` | Hash | HTML attributes for the `<tbody>` (part :tbody) |
| `row_html` | Hash, Proc | HTML attributes applied to each `<tr>` in the body (part :row). Either a plain Hash (applied to every row) or a callable taking the row object and returning a Hash (so callers can style rows conditionally, e.g. highlighting overdue records). |
| `sort_html` | Hash, Proc | HTML attributes applied to a sortable column's `<a class="table-sort">` (part :sort). Either a plain Hash (applied to every sortable header) or a callable taking the column hash and returning a Hash, following `row_html:`'s pattern, so callers can vary it per column. |
| `filter_html` | Hash | HTML attributes for the filter toolbar's outer element (part :filter), only rendered when `filter:` is given. |
| `filter_form_html` | Hash | HTML attributes for the filter toolbar's `<form>` (part :filter_form). |
| `filter_reset_html` | Hash | HTML attributes for the filter toolbar's Reset link (part :filter_reset), only rendered when `filter: { reset: }` is given. |
| `filter_button_html` | Hash | HTML attributes for a filter field's attached search button (part :filter_button), only rendered for a field carrying `button:` -- see "Filtering" below. |
| `filter_hint_html` | Hash | HTML attributes for the `min_chars:` hint element (part :filter_hint), only rendered when `filter: { min_chars: }` is given -- see "Filtering" below. |
| `frame_html` | Hash | HTML attributes for the `<turbo-frame>` element (part :frame), only rendered when `frame:` is given. |
| `footer_html` | Hash | HTML attributes for the footer slot's wrapper (part :footer), rendered only when the caller sets `slots.footer { ... }` -- see "Footer" below. There is no `footer:` options hash; the footer is slot-only, on/off by whether the block set it. |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.table columns: [{ label: "Name", value: ->(row) { row[:name] } }],
                    data: User.all %>
```

**Styling modifiers**

```ruby
<%= tabler_ui.table columns: columns, data: rows, striped: true, hover: true %>
```

**Nested inside an existing card -- opt out of the card wrapper**

```ruby
<%= tabler_ui.table columns: columns, data: rows, card: false %>
```

**Highlighting rows conditionally via a callable**

```ruby
<%= tabler_ui.table columns: columns, data: rows,
                    row_html: ->(row) { row.overdue? ? { class: "table-danger" } : {} } %>
```

**HTML attributes**

```ruby
<%= tabler_ui.table columns: columns, data: rows,
                    html: { class: "mb-4" }, table_html: { class: "table-xl" },
                    thead_html: { class: "text-uppercase" },
                    tbody_html: { data: { testid: "rows" } },
                    row_html: { class: "align-middle" } %>
```

**Sortable columns**

```ruby
<%= tabler_ui.table columns: [{ label: "Name", sort: :name, value: ->(row) { row[:name] } }],
                    data: rows,
                    sort: { key: params[:sort], dir: params[:dir] },
                    sort_url: ->(key, dir) { users_path(sort: key, dir: dir) } %>
```

**Declarative filter toolbar (auto-submitting GET)**

```ruby
<%= tabler_ui.table columns: columns, data: rows,
                    filter: {
                      url: users_path,
                      hidden: { sort: params[:sort], dir: params[:dir] },
                      fields: [
                        { name: "q", value: params[:q] },
                        { name: "status", type: :select, label: "Status",
                          value: params[:status], include_blank: true,
                          options: %w[active inactive] }
                      ]
                    } %>
```

**Filter slot -- arbitrary form contents in place of fields:**

```ruby
<%= tabler_ui.table columns: columns, data: rows, filter: { url: users_path } do |slots| %>
  <% slots.filter do %>
    <%= tag.input(type: "search", name: "q", value: params[:q], class: "form-control") %>
  <% end %>
<% end %>
```

**Turbo Frame -- String shorthand, sorting/filtering stay in-frame**

```ruby
<%= tabler_ui.table columns: columns, data: rows,
                    sort: { key: params[:sort], dir: params[:dir] },
                    sort_url: ->(key, dir) { users_path(sort: key, dir: dir) },
                    frame: "users-table" %>
```

**Turbo Frame -- Hash form, lazily loaded, no history entries**

```ruby
<%= tabler_ui.table columns: columns, data: [],
                    frame: { id: "users-table", src: users_path, loading: :lazy, advance: false } %>
```

**Footer slot -- a pager that swaps with the table instead of going stale**

```ruby
<%= tabler_ui.table columns: columns, data: rows, frame: "users-table" do |slots| %>
  <% slots.footer do %>
    <%= tabler_ui.pagination current: @pagy.page, total: @pagy.pages,
                             url: ->(n) { users_path(page: n) } %>
  <% end %>
<% end %>
```

**Demos**

**striped, hover, row_html:**

```erb
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
```

**responsive: "sm" (scrolls only below sm, instead of at every width)**

```erb
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
```

**responsive: false (no scroll wrapper)**

```erb
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
```

**mobile: true (card-stacked at all widths; data-label draws the headings)**

```erb
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
```

**frame: (Turbo Frame: sorting, filtering and paging without a page reload; pager in footer:; search button: "Search"; filter min_chars: 3)**

```erb
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
```

**filter min_chars: 3, no frame: (no effect: needs auto-submit + frame: together, so this uses a manual Search button)**

```erb
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
```

#### Tabs -- tabler_ui.tabs

Tabs component for Tabler UI. Renders a `ul.nav` of tab links plus a
matching `.tab-content` pane per tab. Builder-style: the block yields
the component itself, and tabs are added via #tab.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `style` | Symbol, String | Tab style -- :tabs (default), :pills, :card, :underline, :bordered, :segmented. Anything else raises ArgumentError naming the component and the valid values. |
| `fill` | Boolean | Adds `nav-fill` -- equal-width items that fill the available space. Mutually exclusive with :justified. |
| `justified` | Boolean | Adds `nav-justified` -- equal-width items that fill the available space, each within its own equal column. Mutually exclusive with :fill. |
| `vertical` | Boolean | Adds `nav-segmented-vertical`. Only valid together with style: :segmented -- raises ArgumentError otherwise. |
| `html` | Hash | HTML attributes for the outer wrapper (part :root) |
| `nav_html` | Hash | HTML attributes for the `ul.nav` (part :nav) |
| `content_html` | Hash | HTML attributes for the `.tab-content` (part :content) |

**Examples**

**Basic usage with block**

```ruby
<%= tabler_ui.tabs("my-tabs") do |tabs| %>
  <% tabs.tab("First Tab", icon: "home") do %>
    Content for first tab
  <% end %>
  <% tabs.tab("Second Tab") do %>
    Content for second tab
  <% end %>
<% end %>
```

**Card-style / pills / underline**

```ruby
<%= tabler_ui.tabs("card-tabs", style: :card) do |tabs| %>
  ...
<% end %>
```

**Badge as text (badge component's own default colour) or**

```ruby
forwarded badge options
<% tabs.tab("Inbox", badge: "3") %>
<% tabs.tab("Inbox", badge: { text: "3", color: "red" }) %>
```

**HTML attributes -- component-level and per-tab**

```ruby
<%= tabler_ui.tabs("my-tabs", html: { class: "mb-3" },
                    nav_html: { class: "mb-0" },
                    content_html: { class: "p-2" }) do |tabs| %>
  <% tabs.tab("First", html: { class: "fw-bold" }) %>
  <% tabs.tab("Second", html: ->(tab) { { class: "text-danger" } if tab.title == "Second" }) %>
<% end %>
```

**Demos**

**style: :pills, icons, badges**

```erb
<%= tabler_ui.tabs("demo-tabs", style: :pills) do |tabs| %>
  <% tabs.tab("Inbox", icon: "mail", badge: "3") do %>
    You have 3 unread messages.
  <% end %>
  <% tabs.tab("Sent", icon: "send") do %>
    Nothing new here.
  <% end %>
  <% tabs.tab("Archive", badge: { text: "12", color: "red" }) do %>
    12 archived threads.
  <% end %>
<% end %>
```

**style: :tabs, :pills, :underline, :bordered, :segmented side by side**

```erb
<div class="row row-cards">
  <div class="col">
    <div class="text-secondary mb-2">style: :tabs (default)</div>
    <%= tabler_ui.tabs("style-tabs-demo") do |tabs| %>
      <% tabs.tab("One") { "First" } %>
      <% tabs.tab("Two") { "Second" } %>
    <% end %>
  </div>
  <div class="col">
    <div class="text-secondary mb-2">style: :pills</div>
    <%= tabler_ui.tabs("style-pills-demo", style: :pills) do |tabs| %>
      <% tabs.tab("One") { "First" } %>
      <% tabs.tab("Two") { "Second" } %>
    <% end %>
  </div>
  <div class="col">
    <div class="text-secondary mb-2">style: :underline</div>
    <%= tabler_ui.tabs("style-underline-demo", style: :underline) do |tabs| %>
      <% tabs.tab("One") { "First" } %>
      <% tabs.tab("Two") { "Second" } %>
    <% end %>
  </div>
  <div class="col">
    <div class="text-secondary mb-2">style: :bordered</div>
    <%= tabler_ui.tabs("style-bordered-demo", style: :bordered) do |tabs| %>
      <% tabs.tab("One") { "First" } %>
      <% tabs.tab("Two") { "Second" } %>
    <% end %>
  </div>
  <div class="col">
    <div class="text-secondary mb-2">style: :segmented</div>
    <%= tabler_ui.tabs("style-segmented-demo", style: :segmented) do |tabs| %>
      <% tabs.tab("One") { "First" } %>
      <% tabs.tab("Two") { "Second" } %>
    <% end %>
  </div>
</div>
```

**fill: true (equal-width tabs)**

```erb
<%= tabler_ui.tabs("fill-tabs-demo", fill: true) do |tabs| %>
  <% tabs.tab("Inbox") { "First" } %>
  <% tabs.tab("Sent") { "Second" } %>
  <% tabs.tab("Archive") { "Third" } %>
<% end %>
```

**style: :segmented, vertical: true**

```erb
<%= tabler_ui.tabs("segmented-vertical-demo", style: :segmented, vertical: true) do |tabs| %>
  <% tabs.tab("One") { "First" } %>
  <% tabs.tab("Two") { "Second" } %>
  <% tabs.tab("Three") { "Third" } %>
<% end %>
```

### Content

#### Alert -- tabler_ui.alert

Alert component for Tabler UI
Displays contextual feedback messages

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `color` | String | Alert color -- validated against TablerUi::Color (Tabler palette + Bootstrap semantic names). Defaults to "info". |
| `title` | String, nil | Optional alert title |
| `text` | String, nil | Alert body text (simple string case; see also the :body slot for rich content) |
| `icon` | String, Boolean, nil | Tabler icon name, or false to suppress the color's default icon |
| `dismissible` | Boolean | Whether the alert can be dismissed (default: false) |
| `important` | Boolean | Important style with colored background (default: false) |
| `url` | String, nil | Optional action link URL |
| `link_text` | String, nil | Action link text (default: "Learn more") |
| `minor` | Boolean | Transparent background, bordered style (default: false) |
| `link_style` | Symbol | :link (default, bold underline-free) or :action (underlined, no bold) for the action link's style |
| `html` | Hash | HTML attributes for the root .alert element (part :root) |
| `title_html` | Hash | HTML attributes for the .alert-heading (part :title), only applied when a title renders |
| `icon_html` | Hash | HTML attributes for the icon's root <svg> (part :icon) -- there is no wrapper element, so the hook lands directly on the svg. Only applied when an icon renders. |
| `link_html` | Hash | HTML attributes for the `.alert-link`/`.alert-action` action link (part :link). Only applied when :url renders one. |
| `dismiss_html` | Hash | HTML attributes for the `.btn-close` dismiss link (part :dismiss), only applied when :dismissible renders one. See #dismiss_attributes. |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.alert color: "success", text: "Your changes have been saved!" %>
```

**With title and dismissible**

```ruby
<%= tabler_ui.alert color: "danger", title: "Error", text: "Something went wrong.", dismissible: true %>
```

**Important alert**

```ruby
<%= tabler_ui.alert color: "warning", text: "Your trial expires in 3 days.", important: true %>
```

**With icon**

```ruby
<%= tabler_ui.alert color: "info", text: "New update available.", icon: "download" %>
```

**With a rich body via the body slot**

```ruby
<%= tabler_ui.alert color: "success" do |slots| %>
  <% slots.body do %>
    <strong>Success!</strong> Your account has been created.
  <% end %>
<% end %>
```

**With an action link**

```ruby
<%= tabler_ui.alert color: "info", text: "New update available.", url: "/changelog", link_text: "See what's new" %>
```

**HTML attributes**

```ruby
<%= tabler_ui.alert text: "Saved!", html: { class: "mb-4" },
                    title: "Done", title_html: { class: "text-uppercase" },
                    icon_html: { data: { testid: "alert-icon" } } %>
```

**link_html: and dismiss_html:**

```ruby
<%= tabler_ui.alert text: "New update available.", url: "/changelog",
                    link_html: { data: { testid: "changelog-link" } },
                    dismissible: true, dismiss_html: { class: "hook-extra-class" } %>
```

**Demos**

**colors, dismissible, important, icon, action link**

```erb
<%= tabler_ui.alert color: "success", text: "Your changes have been saved!" %>
<%= tabler_ui.alert color: "danger", title: "Error", text: "Something went wrong.", dismissible: true %>
<%= tabler_ui.alert color: "warning", text: "Your trial expires in 3 days.", important: true %>
<%= tabler_ui.alert color: "info", text: "New update available.", url: "#", link_text: "See what's new" %>
```

**minor: true (transparent background, neutral border)**

```erb
<%= tabler_ui.alert color: "info", text: "Minor style alert.", minor: true %>
```

**color: 'muted' (alert-only colour value)**

```erb
<%= tabler_ui.alert color: "muted", text: "Muted alert." %>
```

**link_style: :action (underlined action link instead of the default alert-link)**

```erb
<%= tabler_ui.alert color: "info", text: "New update available.", url: "#", link_text: "See what's new", link_style: :action %>
```

#### Avatar -- tabler_ui.avatar

Avatar component for Tabler UI. Renders one of three things, by precedence:

1. `image:` -- a `<span class="avatar">` with a CSS background-image
2. `initials:` -- a `<span class="avatar">` with the initials text and a colour derived from them
3. otherwise -- a deterministic identicon `<svg>`, seeded from `name`

An `overlay` slot nests a status dot or brand chip inside the root element. Image/initials modes only -- an `<svg>` can't host an HTML overlay, so passing `overlay` to a generated identicon raises `ArgumentError`.

Render a status-dot overlay with `tag.span(class: "badge bg-success")` and **no block**. A `do...end` block leaves whitespace inside the tag, which breaks the CSS rule that sizes and positions the dot (it requires a badge with no child nodes at all, not even whitespace) -- the dot silently falls back to a flat, unsized 10px circle. `badge-dot` does not fix this either; it is hardcoded to 10px.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `initials` | String | Initials text (e.g. "JD"). Ignored when :image is given. |
| `name` | String | Seeds the generated identicon when neither :image nor :initials is given. |
| `image` | String | Image URL. Takes precedence over :initials and :name. |
| `size` | String, Symbol | Avatar size, rendered as avatar-<size> (default: "sm") |
| `shape` | String, Symbol | Avatar shape, rendered as rounded-<shape> (default: "rounded" for image/initials, "rounded-0" for the generated identicon) |
| `show_details` | Boolean | Render a title/subtitle block next to the avatar |
| `title` | String | Shown in the details block |
| `subtitle` | String | Shown in the details block |
| `cover` | Boolean | Adds avatar-cover, the "overlaps the card header" modifier |
| `html` | Hash | HTML attributes for the root <span>/<svg> (part :root) |
| `details_html` | Hash | HTML attributes for the show_details wrapper <div> (part :details) |

**Examples**

**Initials**

```ruby
<%= tabler_ui.avatar initials: "JD", size: "md" %>
```

**Image (takes precedence over initials/name)**

```ruby
<%= tabler_ui.avatar image: user_avatar_url(@user), size: "lg" %>
```

**Generated identicon, seeded from name**

```ruby
<%= tabler_ui.avatar name: "Ada Lovelace" %>
```

**Overlay slot**

```ruby
<%= tabler_ui.avatar initials: "JD" do |slots| %>
  <% slots.overlay { tag.span(class: "badge bg-success") } %>
<% end %>
```

**With details**

```ruby
<%= tabler_ui.avatar initials: "JD", show_details: true, title: "Jane Doe", subtitle: "Admin" %>
```

**HTML attributes on the root <span>/<svg> and the details <div>**

```ruby
<%= tabler_ui.avatar initials: "JD", html: { class: "me-2" }, show_details: true, details_html: { class: "ms-1" } %>
```

**Demos**

**initials, image, generated identicon, sizes, show_details**

```erb
<%= tabler_ui.avatar initials: "JD", size: "md" %>
<%= tabler_ui.avatar image: "https://picsum.photos/200", size: "md" %>
<%= tabler_ui.avatar name: "Ada Lovelace", size: "md" %>
<%= tabler_ui.avatar initials: "SM", size: "xl" %>
<%= tabler_ui.avatar initials: "JD", show_details: true, title: "Jane Doe", subtitle: "Admin" %>
```

**cover: true (pulls the avatar up over a banner via negative margin)**

```erb
<div>
  <div class="bg-blue" style="height: 60px; border-radius: 4px;"></div>
  <%= tabler_ui.avatar initials: "JD", size: "xl", cover: true %>
</div>
```

**overlay slot for a status dot, shown at size md and xl to compare scaling**

```erb
<span class="me-3"><%= tabler_ui.avatar initials: "JD", size: "md" do |slots| %>
  <% slots.overlay do %><%= tag.span(class: "badge bg-success") %><% end %>
<% end %></span>
<span><%= tabler_ui.avatar initials: "SM", size: "xl" do |slots| %>
  <% slots.overlay do %><%= tag.span(class: "badge bg-success") %><% end %>
<% end %></span>
```

#### Badge -- tabler_ui.badge

Badge component for Tabler UI
Displays small count and labeling components

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `text` | String | Badge text |
| `color` | String | Color variant -- validated against TablerUi::Color (Tabler palette + Bootstrap semantic names) |
| `light` | Boolean | Use light/subtle variant (default: false) |
| `pill` | Boolean | Rounded pill shape (default: false) |
| `notification` | Boolean | Empty notification dot (default: false) |
| `blink` | Boolean | Blinking animation for notification dots (default: false) |
| `outline` | Boolean | Outline variant, i.e. "badge-outline" (default: false) |
| `dot` | Boolean | Fixed 10px dot ("badge-dot"); ignores badge-sm/badge-lg. Cannot combine with text:, icon: or content: (raises ArgumentError) (default: false) |
| `icon` | String | Tabler icon name |
| `icon_only` | Boolean | Icon-only style, zeroes horizontal padding ("badge-icononly"). Only meaningful with an icon and no text/content -- combining with text/content raises ArgumentError (default: false) |
| `url` | String | URL to make the badge a link (renders <a> instead of <span>) |
| `size` | String, Symbol | Badge size (:sm or :lg) |
| `content` | String, ActiveSupport::SafeBuffer | Block/caller-supplied body content. A plain String is escaped like any other <%= %> output; only a value that already arrived as an ActiveSupport::SafeBuffer is trusted verbatim. |
| `html` | Hash | HTML attributes for the root <a>/<span> (part :root) |

**Examples**

**Basic badge**

```ruby
<%= tabler_ui.badge text: "New", color: "blue" %>
```

**Light variant**

```ruby
<%= tabler_ui.badge text: "Pending", color: "yellow", light: true %>
```

**Pill badge**

```ruby
<%= tabler_ui.badge text: "4", color: "red", pill: true %>
```

**Notification dot (no mandatory argument at all)**

```ruby
<%= tabler_ui.badge color: "red", notification: true %>
```

**Blinking notification**

```ruby
<%= tabler_ui.badge color: "red", notification: true, blink: true %>
```

**Outline variant**

```ruby
<%= tabler_ui.badge text: "Draft", color: "secondary", outline: true %>
```

**With icon**

```ruby
<%= tabler_ui.badge text: "Star", color: "yellow", icon: "star" %>
```

**As link**

```ruby
<%= tabler_ui.badge text: "Click me", color: "blue", url: "/path" %>
```

**With size**

```ruby
<%= tabler_ui.badge text: "Small", color: "green", size: :sm %>
<%= tabler_ui.badge text: "Large", color: "green", size: :lg %>
```

**Fixed-size dot (no content -- a dot and content are mutually exclusive)**

```ruby
<%= tabler_ui.badge color: "red", dot: true %>
```

**Icon-only badge (no padding-x -- only meaningful without text/content)**

```ruby
<%= tabler_ui.badge color: "blue", icon: "star", icon_only: true %>
```

**HTML attributes on the root <a>/<span>**

```ruby
<%= tabler_ui.badge text: "New", html: { class: "me-2", data: { testid: "new-badge" } } %>
```

**Demos**

**colors, light, pill, outline, icon, notification**

```erb
<%= tabler_ui.badge text: "New", color: "blue" %>
<%= tabler_ui.badge text: "Pending", color: "yellow", light: true %>
<%= tabler_ui.badge text: "4", color: "red", pill: true %>
<%= tabler_ui.badge text: "Draft", color: "secondary", outline: true %>
<%= tabler_ui.badge text: "Star", color: "yellow", icon: "star" %>
<%= tabler_ui.badge color: "red", notification: true, blink: true %>
```

**dot: true (fixed 10px dot; raises if combined with text/icon/content)**

```erb
<%= tabler_ui.badge color: "red", dot: true %>
<%= tabler_ui.badge color: "green", dot: true %>
```

**icon_only: true (zeroes horizontal padding; raises if combined with text)**

```erb
<%= tabler_ui.badge color: "blue", icon: "star", icon_only: true %>
```

#### Badge list -- tabler_ui.badge_list

BadgeList component for Tabler UI. Renders a `.badges-list` wrapper --
a flex container (gap: var(--tblr-list-gap), see tabler.css) meant to
hold several `tabler_ui.badge` calls, filled in via a `body` slot.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `html` | Hash | HTML attributes for the outer `.badges-list` (part :root) |

**Examples**

```ruby
<%= tabler_ui.badge_list do |slots| %>
  <% slots.body do %>
    <%= tabler_ui.badge text: "New" %>
    <%= tabler_ui.badge text: "Hot" %>
  <% end %>
<% end %>
```

**HTML attribute**

```ruby
<%= tabler_ui.badge_list html: { class: "mb-2" } do |slots| %>
  <% slots.body do %><%= tabler_ui.badge text: "New" %><% end %>
<% end %>
```

**Demos**

**wraps several badges in a flex .badges-list container**

```erb
<%= tabler_ui.badge_list do |slots| %>
  <% slots.body do %>
    <%= tabler_ui.badge text: "New" %>
    <%= tabler_ui.badge text: "Hot" %>
  <% end %>
<% end %>
```

#### Breadcrumb -- tabler_ui.breadcrumb

Breadcrumb navigation component for Tabler UI. Builder-style: the block
yields the component itself, and entries are added via #item.

##### Accessibility

The `<ol class="breadcrumb">` sits inside a `<nav>` landmark with a
translated `aria-label`. The current item (see `#current?`) renders as
plain text, not a link, with the `active` class and `aria-current="page"`:

  <nav aria-label="breadcrumb">
    <ol class="breadcrumb">
      <li class="breadcrumb-item"><a href="#">Home</a></li>
      <li class="breadcrumb-item active" aria-current="page">Data</li>
    </ol>
  </nav>

##### Current item resolution

If no item is marked `active: true`, the *last* item added is treated
as current automatically -- no link, `active` class, `aria-current="page"`
-- even if it has a `url:`. As soon as any item is given `active: true`,
the automatic last-item behaviour turns off entirely: only the
explicitly marked item(s) are current, and every other item, including
the last, renders normally based on its own `url:`.

##### The `link_html:` hook and non-linked items

`link_html:` only reaches the `<a>` element. An item with no `url:`, or
the current item (which never links, even with a `url:`), renders as
bare text with no `<a>` to apply it to -- `link_html:` is silently
skipped in that case. Target the `<li>` instead via the item's own
`html:` (part :item) when you need to reach a non-linked item.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `style` | Symbol, String | One of `:dots`, `:arrows`, `:bullets` -- selects the divider glyph. `nil` (the default) renders the plain "/" divider. Anything else raises `ArgumentError`. |
| `muted` | Boolean | Renders links in a muted (secondary) colour via `breadcrumb-muted`. |
| `html` | Hash | HTML attributes for the `<ol class="breadcrumb">` (part :root) |
| `link_html` | Hash, #call | HTML attributes for every item's `<a>` (part :link) -- a Hash, or a callable taking the item. Only applied when the item renders as a link -- see "The `link_html:` hook and non-linked items" above. |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.breadcrumb do |breadcrumb| %>
  <% breadcrumb.item("Home", url: "/") %>
  <% breadcrumb.item("Library", url: "/library") %>
  <% breadcrumb.item("Data") %>
<% end %>
```

**Divider style and muted links**

```ruby
<%= tabler_ui.breadcrumb(style: :arrows, muted: true) do |breadcrumb| %>
  ...
<% end %>
```

**Explicit current item (overrides the last-item default)**

```ruby
<%= tabler_ui.breadcrumb do |breadcrumb| %>
  <% breadcrumb.item("Home", url: "/") %>
  <% breadcrumb.item("Reports", url: "/reports", active: true) %>
  <% breadcrumb.item("2024", url: "/reports/2024") %>
<% end %>
```

**HTML attributes -- root and per-item**

```ruby
<%= tabler_ui.breadcrumb(html: { class: "mb-3" }) do |breadcrumb| %>
  <% breadcrumb.item("Home", url: "/", html: { class: "fw-bold" }) %>
  <% breadcrumb.item("Library", url: "/library",
                      html: ->(item) { { class: "text-danger" } if item.title == "Library" }) %>
<% end %>
```

**link_html: -- HTML attributes on the `<a>` element itself (linked items only)**

```ruby
<%= tabler_ui.breadcrumb(link_html: { class: "fw-bold" }) do |breadcrumb| %>
  <% breadcrumb.item("Home", url: "/") %>
  <% breadcrumb.item("Data") %>
<% end %>
```

**Demos**

**style: :arrows, muted**

```erb
<%= tabler_ui.breadcrumb(style: :arrows, muted: true) do |breadcrumb| %>
  <% breadcrumb.item("Home", url: "#") %>
  <% breadcrumb.item("Library", url: "#") %>
  <% breadcrumb.item("Data") %>
<% end %>
```

#### Button -- tabler_ui.button

Button component for Tabler UI. Renders a Bootstrap/Tabler styled
`<a>` (via `link_to`) when `method:` is the default `:get`, or a
`<form>`/`<button>` (via `button_to`) for any other HTTP method --
unless `turbo: true` is given, in which case a non-GET method also
renders as a plain `<a>` (see #turbo_link? and "Turbo" below).

##### Turbo

No `turbo-rails` dependency -- only markup is emitted. `confirm:` and
`turbo:` are inert without Turbo loaded in the host app.

- `confirm:` renders `data-turbo-confirm="..."` on the rendered element
  (read by Turbo, not the old rails-ujs `data-confirm`).
- `turbo: true` renders a non-GET action as `<a data-turbo-method="...">`
  instead of `button_to`'s `<form>`. `button_to` nests a `<form>` inside
  the page's own form (e.g. a delete button on an edit form), which is
  invalid HTML that browsers silently mangle -- `turbo: true` avoids
  that. No-op when `method:` is `:get` (the default); does not raise.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `text` | String | Button label |
| `color` | String | Color variant -- a Tabler/Bootstrap colour name, plus the brand and muted variants ("github", "x", "muted", ...) that only buttons accept. Default: "primary". Invalid values raise `ArgumentError`. |
| `outline` | Boolean | Outline variant, i.e. `btn-outline-<color>` (default: false) |
| `size` | String, Symbol | Button size, rendered as `btn-<size>` |
| `shape` | String | `pill` (btn-pill) or `square` (btn-square) |
| `icon_only` | Boolean | Icon-only style, i.e. `btn-icon` (default: false) |
| `action` | Boolean | Action button style -- transparent/compact/hover-highlight (`btn-action`); replaces the color/outline/shape/icon_only classes (default: false) |
| `loading` | Boolean | Loading style (`btn-loading`); only sets `pointer-events: none`, not `disabled` -- pass `disabled: true` too if the button must also be unfocusable (default: false) |
| `floating` | Boolean | Fixed-position floating style (`btn-floating`) (default: false) |
| `animate_icon` | Boolean, String | Animates the icon on hover/focus (`btn-animate-icon`). `true` for the base slide animation, or one of `rotate`, `shake`, `tada`, `pulse`, `move-start` for that modifier. Modifiers do not compose. |
| `ghost` | Boolean | Ghost style, appends `btn-ghost` alongside `btn-<color>` (default: false). Raises `ArgumentError` if combined with `outline: true` -- Tabler defines no outline+ghost combination. |
| `url` | String | URL for the button (default: "#") |
| `method` | Symbol, String | HTTP method. `:get` (default) renders `link_to`; any other value renders `button_to`. |
| `target` | String | Rendered as `target="..."` |
| `title` | String | Rendered as `title="..."` |
| `disabled` | Boolean | Rendered as `disabled="..."` |
| `data` | Hash | Data attributes, merged with the html: hook's :data |
| `icon` | String | Tabler icon name, rendered before the text |
| `confirm` | String | Confirmation prompt; renders as `data-turbo-confirm="..."`, merged into `:data`. See "Turbo" above. |
| `turbo` | Boolean | Render a non-GET action as a Turbo link instead of `button_to`'s `<form>`. No-op when `method:` is `:get` (default: false). See "Turbo" above. |
| `html` | Hash | HTML attributes for the root <a>/<button> (part :root) |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.button text: "Save", color: "primary", url: "/save" %>
```

**Outline, sized, pill-shaped**

```ruby
<%= tabler_ui.button text: "Cancel", color: "secondary", outline: true, size: :sm, shape: "pill" %>
```

**Destructive action**

```ruby
<%= tabler_ui.button text: "Delete", color: "danger", url: "/widgets/1", method: :delete %>
```

**Icon-only action button**

```ruby
<%= tabler_ui.button icon: "trash", icon_only: true, action: true, url: "/widgets/1", method: :delete %>
```

**HTML attributes on the root <a>/<button>**

```ruby
<%= tabler_ui.button text: "Save", html: { class: "me-2", data: { testid: "save-button" } } %>
```

**Confirmation dialog**

```ruby
<%= tabler_ui.button text: "Delete", color: "danger", url: "/widgets/1", method: :delete,
                     confirm: "Are you sure?" %>
```

**Non-GET action as a Turbo link, no nested <form>**

```ruby
<%= tabler_ui.button text: "Delete", color: "danger", url: "/widgets/1", method: :delete,
                     turbo: true %>
```

**Demos**

**shape: 'pill' (btn-pill, wider padding) vs. default**

```erb
<%= tabler_ui.button text: "Default", color: "primary" %>
<%= tabler_ui.button text: "Pill", color: "primary", shape: "pill" %>
```

**loading: true (sets pointer-events: none only; pair with disabled: true for a real disable)**

```erb
<%= tabler_ui.button text: "Saving...", color: "primary", loading: true, disabled: true %>
```

**animate_icon (hover to see the effect): true = default slide, plus named modifiers**

```erb
<%= tabler_ui.button text: "Next", color: "primary", icon: "arrow-right", animate_icon: true %>
<%= tabler_ui.button text: "Refresh", color: "primary", icon: "refresh", animate_icon: "rotate" %>
<%= tabler_ui.button text: "Notify", color: "primary", icon: "bell", animate_icon: "shake" %>
```

**ghost: true (transparent until hovered; combines with color:, raises with outline: true)**

```erb
<%= tabler_ui.button text: "Ghost", color: "primary", ghost: true %>
<%= tabler_ui.button text: "Ghost danger", color: "danger", ghost: true %>
```

**brand colors (buttons only), plain and outlined**

```erb
<%= tabler_ui.button text: "GitHub", color: "github" %>
<%= tabler_ui.button text: "Twitter", color: "twitter" %>
<%= tabler_ui.button text: "Facebook", color: "facebook", outline: true %>
<%= tabler_ui.button text: "Muted", color: "muted" %>
```

**floating: true (position: fixed -- pinned to the viewport's bottom-left corner, not to this card; shown once)**

```erb
<%= tabler_ui.button text: "Add", color: "primary", icon: "plus", floating: true %>
```

#### Dark mode toggle -- tabler_ui.dark_mode_toggle

Light/dark/system theme toggle for Tabler UI. Renders a single button
wired up to the `tabler-ui--dark-mode` Stimulus controller
(app/javascript/controllers/tabler_ui/dark_mode_controller.js), which
reads/writes localStorage and toggles which of the three inline SVG
icons is visible.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `size` | Symbol | :sm / :lg -- drives the SVG icons' pixel dimensions (default: 24) |
| `title` | String | Rendered as title="..." on the <button> (default: "Switch theme") |
| `html` | Hash | HTML attributes for the outer <div> (part :root) |
| `button_html` | Hash | HTML attributes for the <button> (part :button) |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.dark_mode_toggle %>
```

**Small icons, custom title**

```ruby
<%= tabler_ui.dark_mode_toggle size: :sm, title: "Switch theme" %>
```

**HTML attributes on the root <div> and the <button>**

```ruby
<%= tabler_ui.dark_mode_toggle html: { class: "me-2" }, button_html: { data: { testid: "theme-toggle" } } %>
```

#### Dimmer -- tabler_ui.dimmer

Loading overlay for Tabler UI. Renders a `.dimmer` wrapper around
`.dimmer-content`. `active: true` adds `.dimmer.active`, which shows
the `.loader` spinner and dims the content to 10% opacity.

- Server-side toggle only: re-render with a different `active:` to
  change state (e.g. after a Turbo Stream update).
- The block yields exactly one argument, the SlotContext:
  `do |slots|`, not `do |dimmer, slots|`.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `active` | Boolean | Adds `.active` (default: false) |
| `html` | Hash | HTML attributes for the outer `.dimmer` (part :root) |
| `loader_html` | Hash | HTML attributes for the `.loader` (part :loader) |
| `content_html` | Hash | HTML attributes for the `.dimmer-content` (part :content) |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.dimmer active: @loading do |slots| %>
  <% slots.content do %>Table rows go here<% end %>
<% end %>
```

**HTML attributes**

```ruby
<%= tabler_ui.dimmer active: true, html: { class: "mb-4" },
                      loader_html: { class: "text-primary" },
                      content_html: { class: "p-3" } do |slots| %>
  <% slots.content do %>Content<% end %>
<% end %>
```

**Demos**

**active loading overlay**

```erb
<%= tabler_ui.dimmer active: true do |slots| %>
  <% slots.content do %>
    <div class="p-4">Table rows would render here.</div>
  <% end %>
<% end %>
```

#### Empty -- tabler_ui.empty

Empty component for Tabler UI. Renders an `.empty` panel for no-results /
empty-state screens, with optional `.empty-img`, `.empty-icon`,
`.empty-header`, `.empty-title`, `.empty-subtitle` and `.empty-action`
parts. All parts are siblings in a centred flex column, not nested.

The block yields a single argument, the `SlotContext` -- `do |slots|`, not `do |empty, slots|`.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `title` | String | Rendered as a `<p class="empty-title">`. |
| `subtitle` | String | Rendered as a `<p class="empty-subtitle">`. |
| `header` | String | Large lead text (e.g. an error code), rendered as a `<div class="empty-header">` when no `header` slot is given. |
| `icon` | String | Tabler icon name, rendered via `tabler_ui.icon` inside `.empty-icon` when no `icon` slot is given. |
| `image` | String | Tabler illustration name, rendered via `tabler_ui.illustration` inside `.empty-img` when no `img` slot is given. For an arbitrary external image/URL, use the `img` slot instead. |
| `bordered` | Boolean | empty-bordered (default: false) |
| `html` | Hash | HTML attributes for the outer `.empty` (part :root) |
| `img_html` | Hash | HTML attributes for the `.empty-img` (part :img) |
| `icon_html` | Hash | HTML attributes for the `.empty-icon` (part :icon) |
| `header_html` | Hash | HTML attributes for the `.empty-header` (part :header) |
| `title_html` | Hash | HTML attributes for the `.empty-title` (part :title) |
| `subtitle_html` | Hash | HTML attributes for the `.empty-subtitle` (part :subtitle) |
| `action_html` | Hash | HTML attributes for the `.empty-action` (part :action) |

**Examples**

**Basic usage -- title plus subtitle**

```ruby
<%= tabler_ui.empty title: "No results found",
                     subtitle: "Try adjusting your search or filter." %>
```

**Illustration, title, action buttons**

```ruby
<%= tabler_ui.empty image: "empty", title: "No results found" do |slots| %>
  <% slots.action do %>
    <%= tabler_ui.button text: "New item", url: "#" %>
  <% end %>
<% end %>
```

**404-style header, icon instead of illustration, bordered**

```ruby
<%= tabler_ui.empty icon: "mood-empty", header: "404",
                     title: "Page not found", bordered: true %>
```

**A slot overrides its equivalent plain option**

```ruby
<%= tabler_ui.empty image: "ignored" do |slots| %>
  <% slots.img do %><img src="/custom.svg" alt=""><% end %>
<% end %>
```

**HTML attributes**

```ruby
<%= tabler_ui.empty title: "x", html: { class: "mb-4" },
                     title_html: { class: "text-danger" },
                     subtitle_html: { class: "text-muted" } %>
```

**Demos**

**title, subtitle, illustration, action**

```erb
<%= tabler_ui.empty image: "search", title: "No results found",
                    subtitle: "Try adjusting your search or filter." do |slots| %>
  <% slots.action do %>
    <%= tabler_ui.button text: "Clear filters", url: "#" %>
  <% end %>
<% end %>
```

**header, icon instead of illustration, bordered**

```erb
<%= tabler_ui.empty icon: "mood-empty", header: "404",
                    title: "Page not found", bordered: true %>
```

#### Icon -- tabler_ui.icon

Icon component for Tabler UI. Reads a raw Tabler SVG icon off disk (gem
assets first, then the host app's app/assets/icons/<variant>/ as an
override hook) and emits it with `raw`.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `filled` | Boolean | Use the filled variant instead of outline (default: false) |
| `color` | String | Tabler color name, rendered as "text-<color>" on the root svg |
| `pulse` | Boolean | Adds the "icon-pulse" animation class |
| `tada` | Boolean | Adds the "icon-tada" animation class |
| `rotate` | Boolean | Adds the "icon-rotate" animation class |
| `size` | String | Rendered as "icon-<size>" on the root svg |
| `title` | String | Rendered as a title="..." attribute on the root svg |
| `html` | Hash | HTML attributes for the root <svg> element |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.icon icon: "user" %>
```

**Filled variant, colored, animated**

```ruby
<%= tabler_ui.icon icon: "heart", filled: true, color: "danger", pulse: true %>
```

**HTML attributes on the root <svg>**

```ruby
<%= tabler_ui.icon icon: "user", html: { class: "me-2", data: { testid: "user-icon" } } %>
```

**Demos**

**outline/filled, color, animations, HTML attributes**

```erb
<span class="me-3"><%= tabler_ui.icon icon: "heart" %></span>
<span class="me-3"><%= tabler_ui.icon icon: "heart", filled: true, color: "danger" %></span>
<span class="me-3"><%= tabler_ui.icon icon: "star", filled: true, color: "yellow", pulse: true %></span>
<span class="me-3"><%= tabler_ui.icon icon: "refresh", rotate: true %></span>
<span class="me-3"><%= tabler_ui.icon icon: "bell", tada: true %></span>
<span class="me-3"><%= tabler_ui.icon icon: "user", html: { class: "me-2", data: { testid: "user-icon" } } %></span>
```

#### Illustration -- tabler_ui.illustration

Illustration component for Tabler UI. Reads a raw Tabler illustration SVG
off disk (gem assets first, then the host app's
app/assets/illustrations/<theme>/ as an override hook) and emits it with
`raw`.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `theme` | String | Asset folder to load from: "light" or "dark" (default: "light") |
| `size` | String,Symbol,Integer | Named size (:xs..:xxl) or a raw pixel width; height is scaled proportionally from the source viewBox |
| `html` | Hash | HTML attributes for the root <svg> element |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.illustration name: "empty" %>
```

**Dark theme, sized**

```ruby
<%= tabler_ui.illustration name: "empty", theme: "dark", size: :lg %>
```

**HTML attributes on the root <svg>**

```ruby
<%= tabler_ui.illustration name: "empty", html: { class: "me-2", data: { testid: "empty-illustration" } } %>
```

**Demos**

**light/dark theme, sized**

```erb
<%= tabler_ui.illustration name: "search", size: :sm %>
<%= tabler_ui.illustration name: "search", theme: "dark", size: :sm %>
```

#### Pagination -- tabler_ui.pagination

Pagination component for Tabler UI. Builder-style: the block yields the
component itself, entries added via #item / #gap / #prev / #next.

A second, more common way in: pass `current:`/`total:` and it works
out the item list itself -- see "Computed mode" below.

This component never touches a collection, an ORM, or `params`. Its
entire input is two integers and a way to build a URL (`url:`, a
callable taking a page number).

##### Computed mode

`current:` (1-based) and `total:` (page count) turn on computed mode:
the page range is worked out automatically. `window:` (default 2)
controls how many pages either side of `current` are shown; `url:` is
called once per link actually rendered (never for a gap or a disabled
prev/next).

`current:`/`total:` and a block are mutually exclusive -- calling any
builder method (#item/#gap/#prev/#next) while computed options were
given raises ArgumentError immediately. A block that never calls a
builder method (or no block at all) is fine either way.

`current:` given without `total:` also raises.

###### Degenerate totals

`total: 0` renders an empty `<ul class="pagination">` -- nothing to
paginate, no error. `current:` is ignored in this case.

`total: 1` renders a single active page 1 with both prev and next
disabled, rather than nothing, keeping the markup shape uniform.

Any other `current:` outside `1..total` raises ArgumentError.

##### The range algorithm

Always shows page 1 and the last page, plus a window of `window:`
pages either side of `current`, clamped to `1..total`. A single
hidden page between two shown ones is shown outright instead of a
gap; two or more hidden pages collapse to one `:gap` marker.

##### Turbo Frames

`table`'s `frame:` *emits* a `<turbo-frame>`; pagination's `frame:`
(same key, different job) makes every rendered link *target* one by
id, via `data-turbo-frame="<id>"` -- pagination never emits a
`<turbo-frame>` of its own:

  <%= tabler_ui.table columns: columns, data: rows, frame: "users-table" %>
  <%= tabler_ui.pagination current: page, total: total,
                           url: ->(n) { users_path(page: n) },
                           frame: "users-table" %>

Only `id:` is accepted; `advance:`/`src:`/`loading:` belong to
`table`'s `frame:` and are silently ignored here. No `turbo-rails`
dependency -- `data-turbo-frame` is inert markup without Turbo loaded
in the host app.

##### page-prev / page-next

Tabler's `.page-prev`/`.page-next` classes are `flex: 0 0 50%` each
(built for a two-item "‹ Previous / Next ›" pager) -- combining them
with page-number items overflows the container, so they're applied
only when this is a pure prev/next pager with no `:page` items. Any
pager with page numbers -- every computed-mode render included --
falls back to plain `page-item`.

##### CSS surface

ul.pagination[.pagination-sm|.pagination-lg][.pagination-circle][.pagination-outline]
    li.page-item[.active][.disabled][.page-prev|.page-next -- prev/next-only pagers, see above]
      a.page-link (linkable items) or span.page-link (gaps, disabled prev/next)

##### Accessibility

The `<ul class="pagination">` is wrapped in a `<nav>` landmark with a
translated `aria-label`. The active page's `<li>` gets
`aria-current="page"`. An item only renders as `<a>` when it has a URL
*and* isn't disabled -- disabled prev/next and gaps render as
`<span class="page-link">` instead, so they are never focusable.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `current` | Integer | 1-based current page. Switches on computed mode together with :total -- see the class docs. Defaults to 1 when :total is given without it. |
| `total` | Integer | Total page count. Switches on computed mode. Mandatory if :current is given. |
| `window` | Integer | Pages shown either side of :current in computed mode (default: 2). |
| `url` | #call | Computed mode only -- a callable taking a page number and returning its URL. |
| `size` | Symbol, String | One of :sm, :lg -- pagination-sm/-lg. |
| `circle` | Boolean | Pill-shaped items -- pagination-circle. |
| `outline` | Boolean | Bordered items -- pagination-outline. |
| `prev_label` | String | Component-wide default text for the prev control (falls back to a translated default). A per-call `label:` passed to #prev overrides this. |
| `next_label` | String | Same as :prev_label, for #next. |
| `frame` | String, Hash | Opt-in Turbo Frame *targeting* -- see "Turbo Frames" above. A String is shorthand for `{ id: the String }`. `id:` is mandatory (raises ArgumentError when blank); `advance:`/`src:`/`loading:` are ignored if given -- those belong to `table`'s `frame:` alone. Absent (the default) renders no `data-turbo-frame` attribute at all; the rest of the component's output is unaffected. |
| `html` | Hash | HTML attributes for the `<ul class="pagination">` (part :root) |
| `item_html` | Hash, #call | HTML attributes applied to every `<li class="page-item">` (part :item) -- a plain Hash, or a callable taking the item. Merged underneath any per-item `html:` given to #item/#prev/#next directly. |
| `link_html` | Hash, #call | HTML attributes applied to every `<a class="page-link">`/`<span class="page-link">` (part :link) -- a plain Hash, or a callable taking the item, same contract as :item_html. |

**Examples**

**Builder mode -- full manual control**

```ruby
<%= tabler_ui.pagination do |p| %>
  <% p.prev url: prev_path %>
  <% p.item 1, url: page_path(1) %>
  <% p.gap %>
  <% p.item 3, url: page_path(3), active: true %>
  <% p.item 4, url: page_path(4) %>
  <% p.next url: next_path %>
<% end %>
```

**Computed mode -- the common case**

```ruby
<%= tabler_ui.pagination current: 3, total: 10, url: ->(n) { posts_path(page: n) } %>
```

**size:, circle:, outline:**

```ruby
<%= tabler_ui.pagination current: 1, total: 5, url: ->(n) { "?page=#{n}" },
                         size: :sm, circle: true %>
```

**HTML attributes -- root and per-item**

```ruby
<%= tabler_ui.pagination(html: { class: "mb-3" }) do |p| %>
  <% p.item 1, url: "/1", html: { class: "fw-bold" } %>
  <% p.item 2, url: "/2", html: ->(item) { { class: "text-danger" } if item.page == 2 } %>
<% end %>
```

**frame: -- target a Turbo Frame that a framed table lives in**

```ruby
<%= tabler_ui.pagination current: 3, total: 10, url: ->(n) { posts_path(page: n) },
                         frame: "posts-table" %>
```

**link_html: -- HTML attributes on the `<a>`/`<span>` element itself**

```ruby
<%= tabler_ui.pagination current: 3, total: 10, url: ->(n) { posts_path(page: n) },
                         link_html: { class: "fw-bold" } %>
```

**Demos**

**size: :sm, circle:, outline:**

```erb
<%= tabler_ui.pagination current: 1, total: 5, url: ->(n) { "?page=#{n}" },
                         size: :sm, circle: true, outline: true %>
```

#### Placeholder -- tabler_ui.placeholder

Placeholder component for Tabler UI
Displays skeleton loading states for content

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `type` | Symbol | Placeholder type (:text, :avatar, :image, :button, :card, :list) (default: :text) |
| `width` | Integer | Column width for text/button placeholders (1-12) |
| `size` | String | Size variant (xs, sm, lg) for the :text/fallback placeholder (raises ArgumentError if unrecognized). Not validated for the :avatar type, which uses its own, larger .avatar-* size scale. |
| `animation` | Symbol | Animation type (:glow, :wave) |
| `ratio` | String | Aspect ratio for images (1x1, 4x3, 16x9, 21x9) |
| `color` | String | Tabler color name, validated via TablerUi::Color and rendered as "btn-<color>" on the :button type |
| `lines` | Array<Integer> | Column widths for multiple text lines |
| `rounded` | Boolean | Whether the :avatar placeholder is rounded (default: true) |
| `show_image` | Boolean | Show the image block in the :card placeholder (default: true) |
| `show_button` | Boolean | Show the button block in the :card placeholder (default: true) |
| `html` | Hash | HTML attributes for the active type's own root element |
| `body_html` | Hash | HTML attributes for the :card type's inner .card-body |

**Examples**

**Basic text placeholder**

```ruby
<%= tabler_ui.placeholder type: :text, width: 9 %>
```

**Multiple text lines**

```ruby
<%= tabler_ui.placeholder type: :text, lines: [10, 11, 8] %>
```

**Avatar placeholder**

```ruby
<%= tabler_ui.placeholder type: :avatar %>
```

**Image placeholder**

```ruby
<%= tabler_ui.placeholder type: :image, ratio: "21x9" %>
```

**Button placeholder**

```ruby
<%= tabler_ui.placeholder type: :button, width: 4, color: "primary" %>
```

**Card placeholder with glow animation**

```ruby
<%= tabler_ui.placeholder type: :card, animation: :glow %>
```

**HTML attributes -- the card's outer wrapper vs. its inner body**

```ruby
<%= tabler_ui.placeholder type: :card, html: { class: "mb-3" }, body_html: { class: "p-4" } %>
```

**Demos**

**text, avatar, image, button, list, animation**

```erb
<%= tabler_ui.placeholder type: :text, lines: [10, 11, 8] %>
<%= tabler_ui.placeholder type: :avatar %>
<div class="mb-2"><%= tabler_ui.placeholder type: :image, ratio: "21x9" %></div>
<%= tabler_ui.placeholder type: :button, width: 4, color: "primary" %>
<%= tabler_ui.placeholder type: :text, width: 6, animation: :glow %>
```

#### Progress -- tabler_ui.progress

Progress bar component for Tabler UI.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `percent` | Numeric | Clamped to 0..100 (default: 0). Mutually exclusive with `indeterminate:` (raises ArgumentError if both given). |
| `color` | String | Tabler palette / Bootstrap semantic colour name (validated via TablerUi::Color, raises ArgumentError if unknown), or `"auto"` to resolve success/warning/danger from `percent`. Defaults to "primary". |
| `height` | String | CSS height for the outer bar, e.g. "8px" |
| `label` | String | Text shown in a label row above the bar |
| `show_percent` | Boolean | Show the rounded percentage -- next to the label when `label:` is given, or as a visually-hidden span inside the bar otherwise |
| `size` | String, Symbol | :sm / :lg -- progress-<size> |
| `striped` | Boolean | .progress-bar-striped |
| `animated` | Boolean | .progress-bar-animated |
| `indeterminate` | Boolean | Switches to `.progress-bar-indeterminate`'s sweep animation. Omits `width` and `aria-valuenow` (value is unknown). Mutually exclusive with `percent:` (raises ArgumentError). |
| `separated` | Boolean | Adds `.progress-separated` to the track. No visible effect with a single bar -- only matters for stacked progress bars, which this component does not yet render. |
| `html` | Hash | HTML attributes for the outer .progress <div> (part :root) |
| `bar_html` | Hash | HTML attributes for the inner .progress-bar <div> (part :bar) |
| `label_html` | Hash | HTML attributes for the label row <div> (part :label), only rendered when label_row? is true |

**Examples**

**Basic usage (percent defaults to 0)**

```ruby
<%= tabler_ui.progress %>
<%= tabler_ui.progress percent: 42 %>
```

**Auto color -- picks success/warning/danger from the percentage**

```ruby
<%= tabler_ui.progress percent: 82, color: "auto" %>
```

**Striped + animated**

```ruby
<%= tabler_ui.progress percent: 60, striped: true, animated: true %>
```

**Label row with the percentage**

```ruby
<%= tabler_ui.progress percent: 60, label: "Uploading", show_percent: true %>
```

**Custom height and size**

```ruby
<%= tabler_ui.progress percent: 30, height: "4px", size: :sm %>
```

**HTML attributes on all three parts**

```ruby
<%= tabler_ui.progress percent: 50,
                       html: { class: "mb-3" },
                       bar_html: { data: { testid: "upload-bar" } },
                       label_html: { class: "mb-2" } %>
```

**Demos**

**auto color, striped/animated, labeled**

```erb
<%= tabler_ui.progress percent: 42 %>
<%= tabler_ui.progress percent: 82, color: "auto" %>
<%= tabler_ui.progress percent: 95, color: "auto" %>
<%= tabler_ui.progress percent: 60, striped: true, animated: true %>
<%= tabler_ui.progress percent: 60, label: "Uploading", show_percent: true %>
```

**indeterminate: true (animated unknown-progress bar; raises if combined with percent:)**

```erb
<%= tabler_ui.progress indeterminate: true %>
```

**separated: true (draws a ring per bar; only visible with several bars on one track, which is progress-stacked and not built yet -- inert here for now)**

```erb
<%= tabler_ui.progress percent: 60, separated: true %>
```

#### Rating -- tabler_ui.rating

Star rating input for Tabler UI. Renders a single <select> wired up to
the `tabler-ui--rating` Stimulus controller
(app/javascript/controllers/tabler_ui/rating_controller.js), which
replaces it with a star-rating.js widget.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `id` | String | HTML id (default: deterministic, derived from :name) |
| `name` | String | <select> name (default: "rating") |
| `value` | Object | Currently selected value |
| `choices` | Array<Hash> | List of { value:, label: } choices. Defaults to #default_choices, a scale from "Excellent" down to "Terrible" sized to max_stars. |
| `required` | Boolean | (default: false) |
| `disabled` | Boolean | (default: false) |
| `size` | String | Forwarded to the Stimulus controller / star-rating.js |
| `color` | String | Validated with TablerUi::Color.validate! (nil is valid) |
| `tooltip` | Boolean | (default: true) |
| `clearable` | Boolean | (default: true) |
| `max_stars` | Integer | (default: 5) |
| `html` | Hash | HTML attributes for the <select> (part :root) |
| `wrapper_html` | Hash | HTML attributes for the wrapping <span> (part :wrapper) that carries the Stimulus controller. The controller lives here, not on the <select>. |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.rating %>
```

**Custom choices, 3-star scale, colored**

```ruby
<%= tabler_ui.rating choices: [{ value: 1, label: "Bad" }, { value: 2, label: "Ok" }, { value: 3, label: "Great" }],
                     max_stars: 3, color: "yellow" %>
```

**HTML attributes on the <select>**

```ruby
<%= tabler_ui.rating html: { class: "me-2", data: { testid: "rating" } } %>
```

**Demos**

**custom choices, colored, clearable**

```erb
<%= tabler_ui.rating name: "quality" %>
<%= tabler_ui.rating name: "delivery", choices: [{ value: 1, label: "Bad" }, { value: 2, label: "Ok" }, { value: 3, label: "Great" }],
                     max_stars: 3, color: "yellow", value: 2 %>
```

**two ratings, same name: -- pass id: explicitly or their DOM ids collide**

```erb
<%= tabler_ui.rating name: "overall", id: "overall-rating-reviewer-a", value: 4 %>
<%= tabler_ui.rating name: "overall", id: "overall-rating-reviewer-b", value: 2 %>
```

#### Ribbon -- tabler_ui.ribbon

Ribbon component for Tabler UI. A small label pinned to a corner of a
`position: relative` parent (typically a card) -- a single, absolutely
positioned element with no required inner structure.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `text` | String | Ribbon label. Optional -- omit for a bare colour corner or an icon-only ribbon. A block, if given, overrides this. |
| `color` | String | Colour, validated against TablerUi::Color. Rendered as `bg-<color>`. |
| `position` | String, Symbol | Vertical edge: `:top` (default) or `:bottom`. Raises ArgumentError for anything else. |
| `align` | String, Symbol | Horizontal edge: `:start` or `:end` (default). |
| `bookmark` | Boolean | Bookmark shape (default: false) |
| `icon` | String | Tabler icon name |
| `html` | Hash | HTML attributes for the root element (part :root) |

**Examples**

**Basic usage -- default position (top) and side (end/right)**

```ruby
<%= tabler_ui.ribbon text: "New", color: "blue" %>
```

**Bottom edge, start (left) side**

```ruby
<%= tabler_ui.ribbon text: "Sale", color: "red", position: :bottom, align: :start %>
```

**Bookmark shape**

```ruby
<%= tabler_ui.ribbon text: "Featured", color: "yellow", bookmark: true %>
```

**Bare coloured corner with an icon, no text**

```ruby
<%= tabler_ui.ribbon icon: "star", color: "yellow" %>
```

**Rich content via a block -- wins over text: when both are given**

```ruby
<%= tabler_ui.ribbon color: "green" do |slots| %>
  <% slots.body do %><strong>Hot</strong><% end %>
<% end %>
```

**HTML attributes on the root element**

```ruby
<%= tabler_ui.ribbon text: "New", html: { class: "me-2" } %>
```

**Demos**

**corner label on a card**

```erb
<div class="card position-relative">
  <%= tabler_ui.ribbon text: "New", color: "blue" %>
  <div class="card-body">Ribbon pinned to the card's top-right corner.</div>
</div>
```

**bookmark shape, bottom/start**

```erb
<div class="card position-relative">
  <%= tabler_ui.ribbon text: "Sale", color: "red", position: :bottom, align: :start, bookmark: true %>
  <div class="card-body">Bookmark-shaped ribbon, bottom-left.</div>
</div>
```

#### Spinner -- tabler_ui.spinner

Loading spinner component for Tabler UI.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `type` | Symbol, String | :border (default) or :grow -- raises ArgumentError naming the component and the valid values for anything else. |
| `size` | String, Symbol | "sm" -- renders spinner-<type>-sm |
| `color` | String | Tabler palette / Bootstrap semantic colour name, validated via TablerUi::Color (raises ArgumentError if unknown). Rendered as text-<color>, since the spinner's CSS border colour is `currentcolor`. nil (the default) renders no colour class. |
| `label` | String | Visually-hidden text for screen readers, read out via role="status". Defaults to a translated "Loading..." (see config/locales/en.yml, tabler_ui.spinner.label). |
| `html` | Hash | HTML attributes for the root <div> (part :root) |

**Examples**

**Basic usage (defaults to spinner-border)**

```ruby
<%= tabler_ui.spinner %>
```

**Grow variant**

```ruby
<%= tabler_ui.spinner type: :grow %>
```

**Small, colored**

```ruby
<%= tabler_ui.spinner size: "sm", color: "blue" %>
```

**Custom accessible label**

```ruby
<%= tabler_ui.spinner label: "Saving..." %>
```

**HTML attributes on the root <div>**

```ruby
<%= tabler_ui.spinner html: { class: "me-2" } %>
```

**Demos**

**border/grow, sizes, colors, custom label**

```erb
<span class="me-3"><%= tabler_ui.spinner %></span>
<span class="me-3"><%= tabler_ui.spinner type: :grow %></span>
<span class="me-3"><%= tabler_ui.spinner size: "sm", color: "blue" %></span>
<span class="me-3"><%= tabler_ui.spinner label: "Saving..." %></span>
```

#### Stat card -- tabler_ui.stat_card

Stat card component for Tabler UI. Displays a labeled metric with an
optional trend indicator, icon, description and "Details" link.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `label` | String | Small header text above the trend |
| `value` | String | The headline metric |
| `icon` | String | Tabler icon name, rendered in a colored box |
| `trend` | String | Percentage trend. Positive renders green with an up arrow, negative renders red with a down arrow. Zero/nil renders no trend indicator at all. |
| `description` | String | Small text under the value |
| `color` | String | Color variant for the icon box -- validated against TablerUi::Color (Tabler palette + Bootstrap semantic names). Defaults to "primary". |
| `url` | String | When present, renders a "Details" link |
| `html` | Hash | HTML attributes for the outer <div class="card"> (part :root) |
| `body_html` | Hash | HTML attributes for the <div class="card-body"> (part :body) |
| `value_html` | Hash | HTML attributes for the value element (part :value) |
| `icon_html` | Hash | HTML attributes for the icon badge (part :icon), only rendered when icon: is present |
| `link_html` | Hash | HTML attributes for the Details link (part :link), only rendered when url: is present |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.stat_card label: "Sales", value: "456", icon: "shopping-cart" %>
```

**With a positive trend**

```ruby
<%= tabler_ui.stat_card label: "Sales", value: "456", trend: 12 %>
```

**With a negative trend, description and Details link**

```ruby
<%= tabler_ui.stat_card label: "New clients", value: "18", trend: -8,
                       description: "vs. last month", url: "/clients" %>
```

**Colored icon**

```ruby
<%= tabler_ui.stat_card label: "Revenue", value: "$9,600", icon: "currency-dollar", color: "green" %>
```

**HTML attributes**

```ruby
<%= tabler_ui.stat_card label: "Sales", value: "456", icon: "shopping-cart",
                       html: { class: "mb-3" },
                       body_html: { data: { testid: "sales-card" } },
                       value_html: { class: "fw-bold" },
                       icon_html: { class: "avatar-rounded" },
                       link_html: { class: "ms-2" } %>
```

**Demos**

**positive trend**

```erb
<%= tabler_ui.stat_card label: "Sales", value: "456", icon: "shopping-cart", trend: 12 %>
```

**negative trend, description, link**

```erb
<%= tabler_ui.stat_card label: "New clients", value: "18", trend: -8,
                        description: "vs. last month", url: "#" %>
```

**colored icon**

```erb
<%= tabler_ui.stat_card label: "Revenue", value: "$9,600", icon: "currency-dollar", color: "green" %>
```

#### Status -- tabler_ui.status

Status component for Tabler UI. Displays status indicators with various
styles and colors: plain text badge, a dot in front of text, a
standalone dot with no text, or the 3-circle "status indicator" style.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `text` | String | Status text (optional for standalone dots/indicators) |
| `color` | String | Color variant, see TablerUi::Color::ALL (default: "blue") |
| `dot` | Boolean | Show status dot in front of the text |
| `animated` | Boolean | Animate the dot or indicator |
| `light` | Boolean | Use the light/subtle variant (renders "status-lite") |
| `standalone` | Boolean | Render as a standalone dot (no text) |
| `indicator` | Boolean | Use the status indicator style (3 circles) |
| `html` | Hash | HTML attributes for the root <span> (part :root) |
| `dot_html` | Hash | HTML attributes for the inner dot <span> (part :dot), only rendered when a dot is shown alongside text (dot: true, standalone/indicator both false) |

**Examples**

**Basic status**

```ruby
<%= tabler_ui.status text: "Active", color: "green" %>
```

**Status with dot**

```ruby
<%= tabler_ui.status text: "Online", color: "green", dot: true %>
```

**Animated status dot**

```ruby
<%= tabler_ui.status text: "Processing", color: "blue", dot: true, animated: true %>
```

**Light variant**

```ruby
<%= tabler_ui.status text: "Pending", color: "yellow", light: true %>
```

**Standalone dot**

```ruby
<%= tabler_ui.status color: "green", dot: true, standalone: true %>
```

**Status indicator**

```ruby
<%= tabler_ui.status color: "red", indicator: true %>
```

**Animated status indicator**

```ruby
<%= tabler_ui.status color: "blue", indicator: true, animated: true %>
```

**HTML attributes on the root <span> and the inner dot <span>**

```ruby
<%= tabler_ui.status text: "Online", dot: true,
                     html: { class: "me-2" }, dot_html: { data: { testid: "status-dot" } } %>
```

**Demos**

**dot, animated, standalone, indicator, light**

```erb
<%= tabler_ui.status text: "Active", color: "green" %>
<%= tabler_ui.status text: "Online", color: "green", dot: true %>
<%= tabler_ui.status text: "Processing", color: "blue", dot: true, animated: true %>
<%= tabler_ui.status text: "Pending", color: "yellow", light: true %>
<%= tabler_ui.status color: "green", dot: true, standalone: true %>
<%= tabler_ui.status color: "red", indicator: true, animated: true %>
```

#### Steps -- tabler_ui.steps

Steps component for Tabler UI. Renders a wizard/progress step
indicator. Builder-style: the block yields the component itself, and
steps are added via #item.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `current` | Integer | 1-based index of the active step (default: 1). Raises ArgumentError if out of range (< 1 or > number of items). |
| `vertical` | Boolean | Render as a vertical list (steps-vertical) |
| `counter` | Boolean | Number the dots instead of plain dots (steps-counter) |
| `color` | String | Tabler palette colour name only -- TablerUi::Color::TABLER (blue, azure, indigo, ...), not the Bootstrap semantic names other components accept. Raises ArgumentError otherwise. |
| `light` | Boolean | Use the light/subtle variant (`steps-<color>-lt`). Has no effect without `color:`. |
| `html` | Hash | HTML attributes for the outer list (part :root) |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.steps do |steps| %>
  <% steps.item("Account") %>
  <% steps.item("Profile") %>
  <% steps.item("Confirm") %>
<% end %>
```

**Marking progress, vertical layout, numbered dots**

```ruby
<%= tabler_ui.steps(current: 2, vertical: true, counter: true) do |steps| %>
  <% steps.item("Account") %>
  <% steps.item("Profile") %>
  <% steps.item("Confirm") %>
<% end %>
```

**Linking earlier steps back**

```ruby
<%= tabler_ui.steps(current: 3) do |steps| %>
  <% steps.item("Account", url: account_path) %>
  <% steps.item("Profile", url: profile_path) %>
  <% steps.item("Confirm") %>
<% end %>
```

**Colour, light variant, and HTML attributes**

```ruby
  <%= tabler_ui.steps(color: "azure", light: true, html: { class: "mb-3" }) do |steps| %>
    <% steps.item("Account", html: { class: "fw-bold" }) %>
    <% steps.item("Profile", html: ->(item) { { class: "text-muted" } if item.title == "Profile" }) %>
  <% end %>

Only one step is active at a time, set via `current:` on the component
-- there is no per-item `active:` flag.
```

**Demos**

**current progress, vertical, counter, color**

```erb
<%= tabler_ui.steps(current: 2, counter: true, color: "azure") do |steps| %>
  <% steps.item("Account", url: "#") %>
  <% steps.item("Profile", url: "#") %>
  <% steps.item("Confirm") %>
<% end %>
```

#### Timeline -- tabler_ui.timeline

Timeline component for Tabler UI. Renders a `ul.timeline` of dated /
ordered events, each an `li.timeline-event` with an icon box
(`.timeline-event-icon`) and a content card (`.timeline-event-card`).
Builder-style: the block yields the component itself, and events are
added via #item.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `simple` | Boolean | Hides the icon column entirely and drops the card's left margin (`timeline-simple`, default: false). |
| `html` | Hash | HTML attributes for the outer `ul.timeline` (part :root) |
| `item_html` | Hash, Proc | HTML attributes for each `li.timeline-event` (part :item). Either a plain Hash (applied to every item) or a callable taking the item and returning a Hash. |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.timeline do |t| %>
  <% t.item icon: "check" do %>
    <strong>Order placed</strong>
    <div class="text-secondary">2 hours ago</div>
  <% end %>
  <% t.item icon: "truck", color: "blue" do %>
    Shipped
  <% end %>
<% end %>
```

**simple: -- hides the icon column entirely**

```ruby
<%= tabler_ui.timeline simple: true do |t| %>
  <% t.item { "Signed up" } %>
<% end %>
```

**An item's card content is entirely up to the caller -- nest a**

```ruby
real card if you want one, the component does not bake card structure in
<% t.item icon: "star" do %>
  <%= tabler_ui.card title: "Milestone" do |slots| %>
    <% slots.body { "5 years!" } %>
  <% end %>
<% end %>
```

**HTML attributes -- component-level and per-item**

```ruby
<%= tabler_ui.timeline html: { class: "mb-4" },
                       item_html: ->(item) { { class: "fw-bold" } if item.color == "red" } do |t| %>
  <% t.item icon: "flag", color: "red", icon_html: { class: "border" },
            card_html: { class: "p-2" } do %>
    Flagged
  <% end %>
<% end %>
```

**Demos**

**icons, colors, nested card content**

```erb
<%= tabler_ui.timeline do |t| %>
  <% t.item icon: "check", color: "green" do %>
    <strong>Order placed</strong>
    <div class="text-secondary">2 hours ago</div>
  <% end %>
  <% t.item icon: "truck", color: "blue" do %>
    Shipped
  <% end %>
  <% t.item icon: "flag", color: "red" do %>
    Flagged for review
  <% end %>
<% end %>
```

### Overlays

#### Carousel -- tabler_ui.carousel

Carousel component for Tabler UI. Renders Bootstrap's
`.carousel > .carousel-inner > .carousel-item` slideshow, plus optional
indicators and prev/next controls. Builder-style: the block yields the
component itself, and slides are added via #item.

##### Which slide is active

Each slide takes its own `active:` flag. If none is marked active, the
first slide added becomes active. Exactly one slide must end up
active -- zero or several raises `ArgumentError` once the block finishes.

##### Autoplay

Autoplays by default (Bootstrap's 5000ms interval) unless tuned via
`interval:`. Pass `interval: false` to disable autoplay while keeping
manual prev/next/indicator navigation.

##### Accessibility

The root carries `role="region"`, `aria-roledescription="carousel"` and
a translated `aria-label`. Each slide carries `role="group"`,
`aria-roledescription="slide"` and a translated "Slide N of M" label.
Indicator buttons get a translated "Slide N" label plus `aria-current`
on the active one; prev/next controls get translated visually-hidden text.

Note: the block yields the component itself (`do |carousel| ... end`), not a SlotContext.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `fade` | Boolean | Cross-fade between slides instead of sliding (`carousel-fade`, default: false) |
| `dark` | Boolean | Dark-variant controls/indicators/caption for use over light backgrounds (`carousel-dark`, default: false) |
| `indicators` | Boolean, Symbol | Indicator dots below the slides -- `true` (default), `false`, or a variant: `:dot`, `:thumb` (renders each indicator as a background-image thumbnail from that slide's `image:`, when present), `:vertical` |
| `controls` | Boolean | Prev/next arrow buttons (default: true) |
| `interval` | Integer, Boolean | Milliseconds between automatic slides, or `false` to disable autoplay. Bootstrap's own 5000ms default applies when omitted. |
| `wrap` | Boolean | Whether the carousel cycles continuously (default: true) or hard-stops at the first/last slide. |
| `keyboard` | Boolean | Whether the carousel responds to arrow keys while focused (default: true). |
| `html` | Hash | HTML attributes for the root `.carousel` (part :root) |
| `inner_html` | Hash | HTML attributes for the `.carousel-inner` (part :inner) |
| `indicators_html` | Hash | HTML attributes for the `.carousel-indicators` (part :indicators) |
| `prev_html` | Hash | HTML attributes for the prev control (part :prev) |
| `next_html` | Hash | HTML attributes for the next control (part :next) |

**Examples**

**Basic usage -- images**

```ruby
<%= tabler_ui.carousel("my-carousel") do |carousel| %>
  <% carousel.item(image: image_path("slide1.jpg")) %>
  <% carousel.item(image: image_path("slide2.jpg"), active: true) %>
  <% carousel.item(image: image_path("slide3.jpg")) %>
<% end %>
```

**Custom slide content instead of image:**

```ruby
<%= tabler_ui.carousel("my-carousel") do |carousel| %>
  <% carousel.item { render "some/partial" } %>
<% end %>
```

**Captions, fade transition, no controls/indicators**

```ruby
<%= tabler_ui.carousel("my-carousel", fade: true, controls: false, indicators: false) do |carousel| %>
  <% carousel.item(image: "a.jpg", caption: "First slide", caption_background: true) %>
<% end %>
```

**Indicator variants and autoplay tuning**

```ruby
<%= tabler_ui.carousel("my-carousel", indicators: :thumb, interval: 3000, wrap: false, keyboard: false) do |carousel| %>
  ...
<% end %>
```

**HTML attributes -- component-level and per-item**

```ruby
<%= tabler_ui.carousel("my-carousel", html: { class: "mb-3" },
                       inner_html: { class: "rounded" },
                       indicators_html: { class: "mb-0" },
                       prev_html: { class: "text-dark" },
                       next_html: { class: "text-dark" }) do |carousel| %>
  <% carousel.item(image: "a.jpg", html: { class: "bg-dark" }, caption: "x", caption_html: { class: "fw-bold" }) %>
<% end %>
```

**Demos**

**captions, indicators: :thumb**

```erb
<%= tabler_ui.carousel("demo-carousel", indicators: :thumb) do |carousel| %>
  <% carousel.item(image: "https://picsum.photos/id/1015/900/300", caption: "Mountains",
                   caption_background: true, active: true) %>
  <% carousel.item(image: "https://picsum.photos/id/1016/900/300", caption: "Canyon",
                   caption_background: true) %>
  <% carousel.item(image: "https://picsum.photos/id/1018/900/300", caption: "River",
                   caption_background: true) %>
<% end %>
```

**dark: true (dark indicators, captions and control icons, for use over light images)**

```erb
<%= tabler_ui.carousel("demo-carousel-dark", dark: true, indicators: :thumb) do |carousel| %>
  <% carousel.item(image: "https://picsum.photos/id/1039/900/300", caption: "Snow",
                   caption_background: true, active: true) %>
  <% carousel.item(image: "https://picsum.photos/id/1043/900/300", caption: "Desert",
                   caption_background: true) %>
  <% carousel.item(image: "https://picsum.photos/id/1044/900/300", caption: "Beach",
                   caption_background: true) %>
<% end %>
```

#### Dropdown -- tabler_ui.dropdown

Dropdown component for Tabler UI. Renders a Bootstrap dropdown menu.
Builder-style: the block yields the component itself, and menu entries
are added via #item, #divider, #header.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `label` | String | Button text |
| `color` | String | Tabler colour name for the toggle button (default: "primary") |
| `align` | Symbol, String | Menu alignment -- :start (default) or :end (also accepted as strings). Other values, including "left"/"right", raise ArgumentError. |
| `direction` | String | Drop direction -- "down" (default), "up", "end", "start", "up-center" or "down-center". Replaces the wrapper's base "dropdown" class; anything else raises ArgumentError. |
| `dark` | Boolean | Adds `dropdown-menu-dark` to the menu. |
| `scrollable` | Boolean | Adds `dropdown-menu-scrollable` to the menu. |
| `arrow` | Boolean | Adds `dropdown-menu-arrow` to the menu, alongside any alignment class. |
| `align_breakpoint` | String | Responsive breakpoint (sm/md/lg/xl/xxl) -- combined with :align to add `dropdown-menu-<bp>-<align>` alongside the base alignment class. Validated via TablerUi::Breakpoint. |
| `html` | Hash | HTML attributes for the outer wrapper (part :root) |
| `toggle_html` | Hash | HTML attributes for the toggle button (part :toggle) |
| `menu_html` | Hash | HTML attributes for the `.dropdown-menu` (part :menu) |

**Examples**

**Basic usage**

```ruby
<%= tabler_ui.dropdown(label: "Actions") do |dropdown| %>
  <% dropdown.item("Edit", url: edit_path) %>
  <% dropdown.item("Delete", url: delete_path, method: :delete) %>
  <% dropdown.divider %>
  <% dropdown.item("Archive", url: archive_path) %>
<% end %>
```

**Alignment and colour**

```ruby
<%= tabler_ui.dropdown(label: "Actions", color: "danger", align: :end) do |dropdown| %>
  ...
<% end %>
```

**HTML attributes -- component-level and per-item**

```ruby
<%= tabler_ui.dropdown(label: "Actions", html: { class: "mb-3" },
                       toggle_html: { class: "btn-sm" },
                       menu_html: { class: "shadow" }) do |dropdown| %>
  <% dropdown.item("Edit", url: edit_path, html: { class: "fw-bold" }) %>
  <% dropdown.item("Delete", url: delete_path,
                    html: ->(item) { { class: "text-danger" } if item.title == "Delete" }) %>
<% end %>
```

**Demos**

**color, align: :end, self-triggering**

```erb
<%= tabler_ui.dropdown(label: "Actions", color: "secondary", align: :end) do |dropdown| %>
  <% dropdown.item("Edit", url: "#", icon: "pencil") %>
  <% dropdown.item("Duplicate", url: "#", icon: "copy") %>
  <% dropdown.divider %>
  <% dropdown.item("Delete", url: "#", icon: "trash") %>
<% end %>
```

**dark: true**

```erb
<%= tabler_ui.dropdown(label: "Actions", dark: true) do |dropdown| %>
  <% dropdown.item("Edit", url: "#", icon: "pencil") %>
  <% dropdown.item("Duplicate", url: "#", icon: "copy") %>
  <% dropdown.divider %>
  <% dropdown.item("Delete", url: "#", icon: "trash") %>
<% end %>
```

**scrollable: true (caps the menu at 13rem and scrolls)**

```erb
<%= tabler_ui.dropdown(label: "Choose", scrollable: true) do |dropdown| %>
  <% (1..12).each do |n| %>
    <% dropdown.item("Item #{n}", url: "#") %>
  <% end %>
<% end %>
```

**arrow: true**

```erb
<%= tabler_ui.dropdown(label: "Actions", arrow: true) do |dropdown| %>
  <% dropdown.item("Edit", url: "#", icon: "pencil") %>
  <% dropdown.item("Delete", url: "#", icon: "trash") %>
<% end %>
```

**arrow: true, align: :end**

```erb
<%= tabler_ui.dropdown(label: "Actions", arrow: true, align: :end) do |dropdown| %>
  <% dropdown.item("Edit", url: "#", icon: "pencil") %>
  <% dropdown.item("Delete", url: "#", icon: "trash") %>
<% end %>
```

**direction: "end"**

```erb
<%= tabler_ui.dropdown(label: "Actions", direction: "end") do |dropdown| %>
  <% dropdown.item("Edit", url: "#", icon: "pencil") %>
  <% dropdown.item("Delete", url: "#", icon: "trash") %>
<% end %>
```

**direction: "start"**

```erb
<%= tabler_ui.dropdown(label: "Actions", direction: "start") do |dropdown| %>
  <% dropdown.item("Edit", url: "#", icon: "pencil") %>
  <% dropdown.item("Delete", url: "#", icon: "trash") %>
<% end %>
```

**direction: "up" (placed here so the menu has room above it)**

```erb
<%= tabler_ui.dropdown(label: "Actions", direction: "up") do |dropdown| %>
  <% dropdown.item("Edit", url: "#", icon: "pencil") %>
  <% dropdown.item("Delete", url: "#", icon: "trash") %>
<% end %>
```

**align: :end, align_breakpoint: "md" (responsive alignment class -- effect only visible once the window crosses the md breakpoint)**

```erb
<%= tabler_ui.dropdown(label: "Actions", align: :end, align_breakpoint: "md") do |dropdown| %>
  <% dropdown.item("Edit", url: "#", icon: "pencil") %>
  <% dropdown.item("Delete", url: "#", icon: "trash") %>
<% end %>
```

#### Modal -- tabler_ui.modal

Modal component for Tabler UI. Renders the three-level
`.modal > .modal-dialog > .modal-content` structure Bootstrap's Modal
JS requires, with optional `.modal-header` / `.modal-body` /
`.modal-footer` parts filled in via slots (or a plain `title:` for a
simple header).

The component renders no trigger -- put `data-bs-toggle="modal"
data-bs-target="#<id>"` on your own button/link.

##### Accessibility

The root `.modal` carries `tabindex="-1"`, `role="dialog"`, and either
`aria-labelledby` (pointing at the rendered `.modal-title`) when a
title is showing, or a translated `aria-label` otherwise. The close
button carries its own translated aria-label.

The block yields exactly one argument, the SlotContext --
`do |slots|`, not `do |modal, slots|`.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `title` | String | Rendered as an `<h5 class="modal-title">` inside the header when no `header` slot is given. |
| `size` | String, Symbol | Dialog size: `sm`, `lg`, `xl`, `fullscreen`, or `fullscreen-sm-down` / `-md-down` / `-lg-down` / `-xl-down` / `-xxl-down`. Mutually exclusive with `:full_width` -- both control the dialog's width. |
| `full_width` | Boolean | modal-full-width -- dialog spans the viewport with a small margin instead of a fixed max-width (default: false) |
| `centered` | Boolean | modal-dialog-centered (default: false) |
| `scrollable` | Boolean | modal-dialog-scrollable (default: false) |
| `blur` | Boolean | modal-blur (backdrop blur) on the root (default: false) |
| `status` | String | Colour for a `.modal-status` strip -- validated against TablerUi::Color |
| `close_button` | Boolean | Whether to render the `.btn-close` (default: true) |
| `html` | Hash | HTML attributes for the root `.modal` (part :root) |
| `dialog_html` | Hash | HTML attributes for the `.modal-dialog` (part :dialog) |
| `content_html` | Hash | HTML attributes for the `.modal-content` (part :content) |
| `header_html` | Hash | HTML attributes for the `.modal-header` (part :header) |
| `body_html` | Hash | HTML attributes for the `.modal-body` (part :body) |
| `footer_html` | Hash | HTML attributes for the `.modal-footer` (part :footer) |

**Examples**

**Basic usage -- title plus body/footer slots**

```ruby
<button data-bs-toggle="modal" data-bs-target="#my-modal">Open</button>
<%= tabler_ui.modal "my-modal", title: "Confirm" do |slots| %>
  <% slots.body do %>Are you sure?<% end %>
  <% slots.footer do %>
    <button class="btn btn-primary">Yes</button>
  <% end %>
<% end %>
```

**Custom header content overrides title:**

```ruby
<%= tabler_ui.modal "my-modal" do |slots| %>
  <% slots.header do %><h3>Custom header</h3><% end %>
<% end %>
```

**Size, centered, scrollable, blur, status strip**

```ruby
<%= tabler_ui.modal "my-modal", size: "lg", centered: true,
                    scrollable: true, blur: true, status: "red" %>
```

**Suppress the close button**

```ruby
<%= tabler_ui.modal "my-modal", close_button: false %>
```

**HTML attributes**

```ruby
<%= tabler_ui.modal "my-modal", title: "Confirm",
                    html: { class: "mb-4" },
                    dialog_html: { class: "modal-lg" },
                    content_html: { class: "border-0" },
                    header_html: { class: "bg-dark" },
                    body_html:   { data: { controller: "foo" } },
                    footer_html: { class: "text-end" } %>
```

**Demos**

**title, body/footer slots, trigger**

```erb
<button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#demo-modal">
  Open modal
</button>

<%= tabler_ui.modal "demo-modal", title: "Confirm" do |slots| %>
  <% slots.body { "Are you sure you want to continue?" } %>
  <% slots.footer do %>
    <button class="btn btn-link link-secondary" data-bs-dismiss="modal">Cancel</button>
    <%= tabler_ui.button text: "Yes, continue", color: "primary" %>
  <% end %>
<% end %>
```

**size: lg, centered, blur, status strip**

```erb
<button class="btn btn-outline-danger" data-bs-toggle="modal" data-bs-target="#demo-modal-danger">
  Delete item
</button>

<%= tabler_ui.modal "demo-modal-danger", title: "Delete item", size: "lg",
                    centered: true, blur: true, status: "danger" do |slots| %>
  <% slots.body { "This action cannot be undone." } %>
<% end %>
```

**full_width: true (spans the viewport; raises if combined with size:)**

```erb
<button class="btn btn-outline-primary" data-bs-toggle="modal" data-bs-target="#demo-modal-full-width">
  Open full-width modal
</button>

<%= tabler_ui.modal "demo-modal-full-width", title: "Full width", full_width: true do |slots| %>
  <% slots.body { "This dialog fills the viewport width with a small margin instead of a fixed max-width." } %>
<% end %>
```

**size: "fullscreen-md-down" (width-dependent -- resize the window to see it flip)**

```erb
<button class="btn btn-outline-primary" data-bs-toggle="modal" data-bs-target="#demo-modal-fullscreen-md">
  Open responsive fullscreen modal
</button>

<%= tabler_ui.modal "demo-modal-fullscreen-md", title: "Responsive fullscreen", size: "fullscreen-md-down" do |slots| %>
  <% slots.body { "Below the md breakpoint this fills the screen; at md and above it's a normal dialog." } %>
<% end %>
```

#### Offcanvas -- tabler_ui.offcanvas

A single `.offcanvas.offcanvas-<edge>` panel, sliding in from one of
the four screen edges, with optional `.offcanvas-header` /
`.offcanvas-body` / `.offcanvas-footer` parts filled in via slots (or
a plain `title:` for a simple header).

Renders no trigger -- add `data-bs-toggle="offcanvas"
data-bs-target="#<id>"` to your own button/link.

##### Accessibility

The root `.offcanvas` carries `tabindex="-1"`, `role="dialog"`, and
either `aria-labelledby` (pointing at the `.offcanvas-title`) when a
title is showing, or a translated `aria-label` when it isn't. The
close button carries its own translated `aria-label`.

Note: the close button lives inside `.offcanvas-header`, so the header
renders whenever a header slot, `title:`, or `close_button:` calls for
it -- not only when a header slot or `title:` is given.

Note: the block yields exactly one argument, the SlotContext --
`do |slots|`, not `do |offcanvas, slots|`.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `title` | String | Rendered as an `<h5 class="offcanvas-title">` inside the header when no `header` slot is given. |
| `position` | String, Symbol | Edge the panel slides in from -- one of `:start` (default), `:end`, `:top`, `:bottom`. Invalid values raise `ArgumentError`. |
| `narrow` | Boolean | `offcanvas-narrow` (fixed 20rem width, default: false) |
| `expand` | String, Symbol | Breakpoint (`sm`/`md`/`lg`/`xl`/`xxl`) at and above which the panel becomes a permanently visible sidebar instead of a slide-in overlay. Bootstrap hides `.offcanvas-header` at that breakpoint, so the close button disappears too -- expected sidebar behaviour, not a bug. Omitted by default (always a slide-in overlay). |
| `backdrop` | Boolean, Symbol, String | Bootstrap's `data-bs-backdrop` option -- omitted (Bootstrap default: true), `false`, or `:static`. |
| `scroll` | Boolean | Bootstrap's `data-bs-scroll` option -- allow body scrolling while the offcanvas is open (default: false) |
| `close_button` | Boolean | Whether to render the `.btn-close` (default: true) |
| `html` | Hash | HTML attributes for the root `.offcanvas` (part :root) |
| `header_html` | Hash | HTML attributes for the `.offcanvas-header` (part :header) |
| `body_html` | Hash | HTML attributes for the `.offcanvas-body` (part :body) |
| `footer_html` | Hash | HTML attributes for the `.offcanvas-footer` (part :footer) |

**Examples**

**Basic usage -- title plus body/footer slots**

```ruby
<button data-bs-toggle="offcanvas" data-bs-target="#my-offcanvas">Open</button>
<%= tabler_ui.offcanvas "my-offcanvas", title: "Filters" do |slots| %>
  <% slots.body do %>Filter form here<% end %>
  <% slots.footer do %>
    <button class="btn btn-primary">Apply</button>
  <% end %>
<% end %>
```

**Custom header content overrides title: (and the built-in close button)**

```ruby
<%= tabler_ui.offcanvas "my-offcanvas" do |slots| %>
  <% slots.header do %><h3>Custom header</h3><% end %>
<% end %>
```

**Edge, narrow width, backdrop and scroll behaviour**

```ruby
<%= tabler_ui.offcanvas "my-offcanvas", position: :end, narrow: true,
                        backdrop: :static, scroll: true %>
```

**Suppress the close button**

```ruby
<%= tabler_ui.offcanvas "my-offcanvas", close_button: false %>
```

**Always-visible sidebar from lg upward**

```ruby
<%= tabler_ui.offcanvas "my-offcanvas", expand: "lg" %>
```

**HTML attributes**

```ruby
<%= tabler_ui.offcanvas "my-offcanvas", title: "Filters",
                        html: { class: "mb-4" },
                        header_html: { class: "bg-dark" },
                        body_html:   { data: { controller: "foo" } },
                        footer_html: { class: "text-end" } %>
```

**Demos**

**position: :end, trigger**

```erb
<button class="btn btn-primary" data-bs-toggle="offcanvas" data-bs-target="#demo-offcanvas">
  Open filters
</button>

<%= tabler_ui.offcanvas "demo-offcanvas", title: "Filters", position: :end do |slots| %>
  <% slots.body { "Filter form goes here." } %>
  <% slots.footer do %>
    <%= tabler_ui.button text: "Apply", color: "primary" %>
  <% end %>
<% end %>
```

**position: :bottom, narrow, backdrop: :static**

```erb
<button class="btn btn-outline-primary" data-bs-toggle="offcanvas" data-bs-target="#demo-offcanvas-bottom">
  Open panel
</button>

<%= tabler_ui.offcanvas "demo-offcanvas-bottom", title: "Details", position: :bottom,
                        backdrop: :static do |slots| %>
  <% slots.body { "This offcanvas won't close on backdrop click." } %>
<% end %>
```

**expand: "lg" (width-dependent -- below lg a normal slide-over; at lg and above it becomes a permanently visible sidebar with its header/close button hidden, per Bootstrap)**

```erb
<button class="btn btn-outline-primary" data-bs-toggle="offcanvas" data-bs-target="#demo-offcanvas-expand">
  Open expandable sidebar
</button>

<%= tabler_ui.offcanvas "demo-offcanvas-expand", title: "Sidebar", expand: "lg" do |slots| %>
  <% slots.body { "Below lg this behaves like any other offcanvas. At lg and above Bootstrap keeps it permanently visible and hides its header (including the close button) -- intended always-open-sidebar behaviour, not a bug." } %>
<% end %>
```

#### Toast -- tabler_ui.toast

Toast component for Tabler UI. Renders a single Bootstrap-driven
`.toast` (optionally wrapped in a positioned `.toast-container`), with
`.toast-header` / `.toast-body` parts filled in via slots (or a plain
`title:` for a simple header).

The component renders no trigger -- put `data-bs-toggle="toast"
data-bs-target="#<id>"` on your own button/link (give the toast an
`id:` via `html: { id: ... }` to target). Trigger wiring is scanned
once at script-load time, so a toast/trigger pair inserted later via
Turbo needs to be shown some other way (e.g. calling `.show()` on the
adopted instance yourself).

##### Accessibility

The root `.toast` carries `role="alert"`, `aria-live="assertive"` and
`aria-atomic="true"` by default. For a lower-priority notification,
override with `role="status" aria-live="polite"` via the `html:` hook.
The close button carries its own translated aria-label.

**Options**

| Name | Type | Description |
| --- | --- | --- |
| `title` | String | Rendered as a `<strong class="me-auto">` inside the header when no `header` slot is given. |
| `color` | String | Colour for the toast, validated against TablerUi::Color, rendered as `toast-<color>`. |
| `autohide` | Boolean | Maps to `data-bs-autohide`. Only rendered when given explicitly (Bootstrap defaults it to true itself). |
| `delay` | Integer | Milliseconds before autohide fires, maps to `data-bs-delay`. Only rendered when given explicitly (Bootstrap defaults it to 5000). |
| `close_button` | Boolean | Whether to render the `.btn-close` (default: true) |
| `position` | String | Fixed placement -- wraps the toast in a `.toast-container.position-fixed`. One of `top-left`, `top-center`, `top-right`, `middle-left`, `middle-center`, `middle-right`, `bottom-left`, `bottom-center`, `bottom-right`. To stack several toasts in one corner, render each with no `position:` inside your own `.toast-container`. |
| `html` | Hash | HTML attributes for the root `.toast` (part :root) |
| `header_html` | Hash | HTML attributes for the `.toast-header` (part :header) |
| `body_html` | Hash | HTML attributes for the `.toast-body` (part :body) |
| `container_html` | Hash | HTML attributes for the `.toast-container`, when `position:` is given (part :container) |
| `close_html` | Hash | HTML attributes for the `.btn-close` button, when `close_button:` is true (part :close) |

**Examples**

**Basic usage -- title plus body slot**

```ruby
<%= tabler_ui.toast title: "Success", color: "success" do |slots| %>
  <% slots.body { "Changes saved." } %>
<% end %>
```

**Custom header content overrides title:**

```ruby
<%= tabler_ui.toast do |slots| %>
  <% slots.header { "Custom header".html_safe } %>
  <% slots.body { "Body text" } %>
<% end %>
```

**Autohide tuning**

```ruby
<%= tabler_ui.toast title: "Heads up", autohide: false %>
<%= tabler_ui.toast title: "Heads up", delay: 8000 %>
```

**Fixed placement (see #position for the full vocabulary)**

```ruby
<%= tabler_ui.toast title: "Saved", position: "top-right" %>
```

**Suppress the close button**

```ruby
<%= tabler_ui.toast title: "Saved", close_button: false %>
```

**HTML attributes**

```ruby
<%= tabler_ui.toast title: "Saved", position: "top-right",
                    html:           { class: "mb-2" },
                    header_html:    { class: "bg-dark" },
                    body_html:      { data: { controller: "foo" } },
                    container_html: { class: "p-4" } %>
```

**close_html: -- HTML attributes on the close button**

```ruby
<%= tabler_ui.toast title: "Saved", close_html: { class: "me-1", data: { testid: "dismiss" } } %>
```

**Demos**

**color, trigger via html: { id: }**

```erb
<button class="btn btn-success" data-bs-toggle="toast" data-bs-target="#demo-toast">
  Show toast
</button>

<div class="toast-container position-fixed bottom-0 end-0 p-3">
  <%= tabler_ui.toast title: "Success", color: "success", html: { id: "demo-toast" } do |slots| %>
    <% slots.body { "Changes saved." } %>
  <% end %>
</div>
```

**position:, autohide: false, delay:**

```erb
<button class="btn btn-outline-warning" data-bs-toggle="toast" data-bs-target="#demo-toast-warning">
  Show sticky warning
</button>

<%= tabler_ui.toast title: "Heads up", color: "warning", autohide: false,
                    position: "top-right", html: { id: "demo-toast-warning" } do |slots| %>
  <% slots.body { "This toast stays until dismissed." } %>
<% end %>
```

## Form builder

`TablerUi::FormBuilder` (`lib/tabler_ui/form_builder.rb`) is an
`ActionView::Helpers::FormBuilder` subclass, Simple-Form style.
Reach it via `tabler_form_with` or `tabler_ui_form_for`
(`lib/tabler_ui/helper.rb`), which each set
`options[:builder] ||= TablerUi::FormBuilder` and delegate to
`form_with`/`form_for`.

```ruby
<%= tabler_form_with model: @user do |f| %>
  <%= f.input :name %>
  <%= f.input :email %>
  <%= f.submit "Save" %>
<% end %>
```

`#input` derives a method name from the DB column type
(`object_type_for_method`) and dispatches to it via `send` --
`:string`, `:text`, `:integer`, `:date`, `:boolean`, `:file` and
`:select` are covered; `:decimal`, `:float`, `:datetime` and
`:time` route through `string_input`/`string_field`'s own
finer-grained dispatch. An unrecognised type (and no explicit
`as:`) raises `ArgumentError` with a message naming the field and
the resolved input method, rather than a bare `NoMethodError`.
Pass `as:` to render it explicitly.

`#error_notification` renders a Tabler alert (via
`tabler_ui.alert`) from `@object.errors.full_messages` when the
object has any errors. Per-field errors render inline: a
`.invalid-feedback` div plus an `is-invalid` class on the field
itself, driven by `has_error?`.

**f.input :name -- default :string**

```erb
<%= f.input :name, hint: "Full legal name", required: true %>
```

**f.input :email -- name-pattern email_field**

```erb
<%= f.input :email, label_description: "we'll never share it" %>
```

**f.input :bio, as: :text**

```erb
<%= f.input :bio, as: :text, input_html: { rows: 3 } %>
```

**f.input :birthday, as: :date_picker**

```erb
<%= f.input :birthday, as: :date_picker %>
```

**f.input :phone -- name-pattern telephone_field**

```erb
<%= f.input :phone %>
```

**f.input :website, as: :floating**

```erb
<%= f.input :website, as: :floating, label: "Website" %>
```

**f.toggle_switch :newsletter**

```erb
<%= f.toggle_switch :newsletter, description: "Product updates, once a month" %>
```

**f.toggle_button :bio_notifications, color:, icon:**

```erb
<%= f.toggle_button :bio_notifications, color: "success", icon: "bell", text: "Notify on profile views" %>
```

**f.input :plan, as: :radio_buttons, selectgroup_buttons: true**

```erb
<%= f.input :plan, as: :radio_buttons, collection: %w[free pro enterprise], selectgroup_buttons: true %>
```

**f.input :interests, as: :check_boxes, selectgroup_pills: true**

```erb
<%= f.input :interests, as: :check_boxes, collection: %w[Design Engineering Marketing Sales], selectgroup_pills: true %>
```

**f.input :role, as: :select**

```erb
<%= f.input :role, as: :select, collection: %w[admin editor viewer] %>
```

**f.input :team, as: :grouped_select**

```erb
<%= f.input :team, as: :grouped_select, collection: { "Engineering" => %w[backend frontend], "Product" => %w[design research] } %>
```

**f.association :manager_id -- no reflection, falls back to select**

```erb
<%= f.association :manager_id, collection: %w[Alice Bob Carol] %>
```

**f.input :color, as: :color**

```erb
<%= f.input :color, as: :color %>
```

**f.input :avatar_rating, as: :rating**

```erb
<%= f.input :avatar_rating, as: :rating, max_stars: 5, color: "yellow" %>
```

**f.input :theme, as: :imagecheck**

```erb
<%= f.input :theme, as: :imagecheck, show_text: true,
                    value_method: :id, image_method: :image_url, text_method: :label,
                    collection: [
                      OpenStruct.new(id: "blue", image_url: "https://picsum.photos/seed/blue/80", label: "Blue"),
                      OpenStruct.new(id: "green", image_url: "https://picsum.photos/seed/green/80", label: "Green")
                    ] %>
```

**f.input :resume, as: :file**

```erb
<%= f.input :resume, as: :file, hint: "PDF, up to 5MB" %>
```

**f.input_field -- naked input, no wrapper/label**

```erb
<%= f.input_field :search_query, input_html: { placeholder: "Naked input, no label/wrapper" } %>
```

**f.input :appointment_at / :salary -- inferred types**

```erb
<p class="text-secondary">
  <code>appointment_at</code> is a <code>:datetime</code> attribute and <code>salary</code> a
  <code>:decimal</code> one. <code>TablerUi::FormBuilder</code> infers both from the model and
  renders a native <code>datetime-local</code> field and a <code>number</code> field with
  <code>step="any"</code> -- no <code>as:</code> needed. This works for plain
  <code>ActiveModel::Attributes</code> objects as well as ActiveRecord ones, because
  <code>object_type_for_method</code> falls back to the class-level
  <code>attribute_types</code> that ActiveModel exposes.
</p>
<%= f.input :appointment_at %>
<%= f.input :salary %>
```

**f.input as: :input_group**

```erb
<%= f.input :salary, as: :input_group, prepend: "$", label: "Salary (as: :input_group)", input_html: { id: "person_salary_input_group" } %>
<%= f.input :website, as: :input_group, append: ".com", label: "Website (as: :input_group)", input_html: { id: "person_website_input_group" } %>
```

