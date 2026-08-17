# Tabler UI

A Rails engine that wraps [Tabler](https://tabler.io/) v1.4.0 (Bootstrap 5) as a
set of Ruby components: `tabler_ui.button ...`, `tabler_ui.card ... do |slots| ... end`,
and so on, plus a `FormBuilder` for Simple-Form-style inputs. Ruby >= 3.1, Rails >= 7.

This file documents the current API. **If you're upgrading from an older copy of
this gem, read [Upgrading from 0.2.x](#upgrading-from-02x) first** — this release
renamed almost every colour/customisation option across the whole component set.

## Installation

```ruby
gem "tabler_ui", git: "https://github.com/webbastelbude/tabler_ui.git"
```

```bash
bundle install
```

### Asset setup

**Requires Sprockets — Propshaft is not supported.** `app/assets/stylesheets/tabler_ui.css`
is a Sprockets directive manifest (`*= require`), which Propshaft cannot process; the gem
declares `sprockets-rails ~> 3.5` as a dependency for this reason. Rails 8's default new-app
pipeline is Propshaft, so an app generated with `rails new` needs Sprockets added
(`bundle add sprockets-rails` is usually enough) before this gem's assets will compile.

Add the stylesheet to `app/assets/stylesheets/application.css`:

```css
/*
 *= require tabler_ui
 */
```

The gem's own `config/importmap.rb` is auto-loaded by the engine, so
`tabler_ui`, its Stimulus controllers, and its bundled dependencies —
`vanillajs-datepicker`, `star-rating.js`, `apexcharts` — are already pinned.
Just import it:

```javascript
// app/javascript/application.js
import "tabler_ui"
```

`tabler_ui.js` self-registers all 14 Stimulus controllers against
`window.Stimulus`, so make sure it's imported after your `controllers/application.js`
sets that up.

### Optional: country flags

```css
/*
 *= require tabler_ui/addons/tabler-flags
 */
```

```erb
<span class="flag flag-de"></span>
```

Over 260 flag SVGs, `app/assets/images/tabler_ui/flags/`.

### Optional: ApexCharts

```css
/*
 *= require apexcharts
 */
```

```erb
<div data-controller="tabler-ui--chart"
     data-tabler-ui--chart-type-value="line"
     data-tabler-ui--chart-options-value='<%= { series: [{ name: "Sales", data: [30, 40, 45] }] }.to_json %>'></div>
```

See `CLAUDE.md` in this repo for fuller ApexCharts examples.

### I18n

Every user-visible default string the gem renders (form error headings, close-button labels,
carousel/pagination/breadcrumb aria-labels, the dark mode toggle's title, and so on) lives in
`config/locales/en.yml` under a `tabler_ui` namespace. Rails' `Rails::Engine` auto-loads it into
`I18n.load_path`, so there's nothing to require. A host app overrides any string the normal Rails
way — add the same key to its own locale file:

```yaml
# config/locales/en.yml
en:
  tabler_ui:
    dark_mode_toggle:
      title: "Toggle theme"
    modal:
      close: "Dismiss"
```

Components that take a `title:`/`text:` option (e.g. `alert`, `modal`) let the caller's value
override the translation on a per-call basis regardless.

### Showcase app

`showcase/` is a small, dev-only Rails app that renders every component with its source snippet
next to it. It ships in the repo but is excluded from the packaged gem. To run it:

```bash
cd showcase
bundle install
bin/rails server -p 3561
```

## Conventions

Every component is called as `tabler_ui.<name>(...)` from a view (the `tabler_ui`
helper is injected into `ActionController::Base` and `ActionMailer::Base` by the
engine). Read this section once; it applies to all 33 components below.

**Mandatory vs. optional.** A component's one or two mandatory values (an icon
name, a tabs container's `id`) are positional. Everything else is keyword
arguments, collected into an options hash. Both look like ordinary keyword
syntax at the call site:

```erb
<%= tabler_ui.icon icon: "user", color: "danger" %>
<%= tabler_ui.tabs id: "my-tabs", style: :pills do |tabs| ... end %>
```

If a mandatory value is missing, the call raises `ArgumentError: tabler_ui.<name>
requires <key>:` rather than rendering something broken.

**`html:` / `<part>_html:` hooks.** There is no `class:` or `custom_class:`
option anywhere. Instead, every meaningful element a component renders exposes
an HTML hook: `html:` for the single/root element, `<part>_html:` for each
named inner part (`title_html:`, `body_html:`, `footer_html:`, …). The hash is
passed straight through to Rails' `tag` helper — set `class`, `data`, `aria-*`,
`id`, anything:

```erb
<%= tabler_ui.card title: "Users",
                    html: { class: "mb-4" },
                    header_html: { class: "bg-dark" } do |slots| %>
  <% slots.body { "..." } %>
<% end %>
```

A caller's `class` **appends** to the component's own classes; every other
attribute **overwrites** (data/aria hashes merge key-by-key). Some hooks accept
a `Proc` instead of a `Hash`, for parts that repeat per item (table rows,
datagrid items, dropdown/nav entries) — the proc is called with that item and
must return a Hash:

```erb
<%= tabler_ui.table columns: columns, data: rows,
                     row_html: ->(row) { row.overdue? ? { class: "table-danger" } : {} } %>
```

**`color:`.** Most components take a `color:` option, validated against a
shared vocabulary (`TablerUi::Color::ALL`) — passing anything else raises
`ArgumentError`. Two families are accepted:

- Bootstrap semantic names: `primary secondary success danger warning info light dark`
- The Tabler palette: `blue azure indigo purple pink red orange yellow lime green teal cyan`

**Blocks.** A component's block is invoked with **exactly one** argument, never
two. Which kind depends on the component:

- **Builder style** (`navbar`, `dropdown`, `tabs`, `settings_page`, `datagrid`) —
  the block yields the **component itself**; you add content via its own
  builder methods (`dropdown.item(...)`, `tabs.tab(...)`).
- **Slot style** (everything else that takes a block: `card`, `alert`,
  `page_header`) — the block yields a `slots` object; you fill named
  slots via `slots.body { ... }`, `slots.footer { ... }`.

```erb
<%= tabler_ui.card title: "Users" do |slots| %>
  <% slots.body { "Not do |card, slots|" } %>
<% end %>

<%= tabler_ui.dropdown label: "Actions" do |dropdown| %>
  <% dropdown.item "Edit", url: edit_path %>
<% end %>
```

Builder methods that take a title/label take it **positionally**
(`dropdown.item("Edit", url: ...)`, not `dropdown.item(title: "Edit", ...)`) —
the old keyword form raises `ArgumentError` naming the method rather than
silently rendering a Hash as content.

**A discarded slot block raises.** For a slot-style component, whatever the block itself
outputs (outside of `slots.<name> { ... }` calls) is captured and thrown away — only content
placed into a slot renders. If a block writes visible content but never calls a slot method,
that content would previously vanish silently; the dispatcher now raises `ArgumentError`
instead, naming the component:

```erb
<%= tabler_ui.card title: "x" do %>Body text<% end %>
<%# ArgumentError: tabler_ui.card's block wrote content but set no slots... %>
```

**`validate!`.** A component class may define a `validate!` instance method; the dispatcher
calls it after a builder block has finished running (so it can check things that are only known
once every item has been added — `steps`' `current:` index, `carousel`'s single active slide,
`accordion`'s single-open constraint) and before the component renders. Raising there surfaces a
plain `ArgumentError` instead of one wrapped in `ActionView::Template::Error`.

## Component reference

### accordion

Builder style. Mandatory `id`.

```erb
<%= tabler_ui.accordion("my-accordion") do |accordion| %>
  <% accordion.item("First item", open: true) do %>
    Content for the first item
  <% end %>
  <% accordion.item("Second item") do %>
    Content for the second item
  <% end %>
<% end %>
```

Single-open by default — each pane closes its siblings via `data-bs-parent`; pass
`multiple: true` to allow more than one open at once. More than one item marked
`open: true` without `multiple: true` raises `ArgumentError` (checked after the block runs).

| Option | Notes |
|---|---|
| `flush:` | removes the default borders/rounded corners |
| `inverted:` | toggle icon before the title |
| `style:` | `:tabs` for the card-like `accordion-tabs` variant |
| `toggle_style:` | `:chevron` (default) or `:plus` |
| `multiple:` | allow more than one item open at once (default `false`) |
| `html:` | hook |

`item(title, open:, icon:, html:, header_html:, body_html:) { content }`.

### alert

```erb
<%= tabler_ui.alert color: "success", text: "Saved!" %>
<%= tabler_ui.alert color: "danger", title: "Error", text: "Something went wrong.", dismissible: true %>
<%= tabler_ui.alert color: "info" do |slots| %>
  <% slots.body { "<strong>Rich</strong> content".html_safe } %>
<% end %>
```

| Option | Notes |
|---|---|
| `color:` | default `"info"` |
| `title:` | renders an `h4.alert-title` |
| `text:` | body text; use the `body` slot instead for rich content |
| `icon:` | Tabler icon name, or `false` to suppress the colour's default icon |
| `dismissible:` | adds a dismiss button, wires up `tabler-ui--alert` |
| `important:` | colored-background style |
| `url:`, `link_text:` | action link (`link_text:` defaults to "Learn more") |
| `html:`, `title_html:`, `icon_html:` | hooks |

### avatar

```erb
<%= tabler_ui.avatar initials: "JD", size: "md" %>
<%= tabler_ui.avatar image: user_avatar_url(@user), size: "lg" %>
<%= tabler_ui.avatar name: "Ada Lovelace" %>  <%# generated identicon %>
```

Renders, in order of precedence: `image:` (background-image span) >
`initials:` (span with an HSL colour derived from the initials) > otherwise a
deterministic generated identicon `<svg>` seeded from `name:`.

| Option | Notes |
|---|---|
| `initials:` | ignored when `image:` given |
| `name:` | seeds the identicon when neither `image:` nor `initials:` given |
| `image:` | takes precedence over both |
| `size:` | default `"sm"` |
| `shape:` | default `"rounded"` (`"rounded-0"` for the identicon) |
| `show_details:`, `title:`, `subtitle:` | details block next to the avatar |
| `html:`, `details_html:` | hooks |

### badge

```erb
<%= tabler_ui.badge text: "New", color: "blue" %>
<%= tabler_ui.badge color: "red", notification: true, blink: true %>
<%= tabler_ui.badge text: "Click me", color: "blue", url: "/path" %>
```

| Option | Notes |
|---|---|
| `text:` | badge label |
| `color:` | |
| `light:` | subtle `bg-<color>-lt` variant |
| `pill:` | rounded-pill shape |
| `notification:` | empty dot |
| `blink:` | animated notification dot |
| `outline:` | outline style |
| `icon:` | Tabler icon name |
| `url:` | renders `<a>` instead of `<span>` |
| `size:` | `:sm` / `:lg` |
| `content:` | escaped like any `<%=`, unless already an `ActiveSupport::SafeBuffer` |
| `html:` | hook |

### breadcrumb

Builder style.

```erb
<%= tabler_ui.breadcrumb do |breadcrumb| %>
  <% breadcrumb.item("Home", url: "/") %>
  <% breadcrumb.item("Library", url: "/library") %>
  <% breadcrumb.item("Data") %>
<% end %>
```

Wrapped in a `<nav>` landmark. The *last* item added is treated as the current page
automatically (plain text, `aria-current="page"`, no link) unless any item is marked
`active: true` explicitly — as soon as one is, only explicitly-marked items are current.

| Option | Notes |
|---|---|
| `style:` | `:dots` / `:arrows` / `:bullets` divider glyph; default plain "/" |
| `muted:` | `breadcrumb-muted`, renders links in a muted colour |
| `html:` | hook |

`item(title, url:, active:, html:)`. Per-item `html:` may be a Hash or a `Proc` taking the item.

### button

Renders `link_to` for `method: :get` (the default), `button_to` for anything
else.

```erb
<%= tabler_ui.button text: "Save", color: "primary", url: save_path %>
<%= tabler_ui.button text: "Delete", color: "danger", url: widget_path(w), method: :delete %>
<%= tabler_ui.button icon: "trash", icon_only: true, action: true, url: widget_path(w), method: :delete %>
```

| Option | Notes |
|---|---|
| `text:` | default `"Button"` (`nil` when `action: true`) |
| `color:` | default `"primary"` |
| `outline:` | `btn-outline-<color>` |
| `size:` | `btn-<size>` |
| `shape:` | `"pill"` or `"square"` |
| `icon_only:` | `btn-icon` |
| `action:` | `btn-action` style, replaces color/outline/shape/icon_only classes |
| `url:` | default `"#"` |
| `method:` | `:get` (default, `link_to`) or anything else (`button_to`) |
| `target:`, `title:`, `disabled:` | passed through |
| `icon:` | rendered before the text |
| `data:` | merged with the `html:` hook's `data:` |
| `html:` | hook |

There is no `to:` option (dropped) — use `url:`.

### card

```erb
<%= tabler_ui.card title: "Card title" do |slots| %>
  <% slots.body { "Content" } %>
  <% slots.footer { "Footer" } %>
<% end %>
```

A `header` slot overrides `title:`. `size:`, `status:` (a colour strip),
`borderless:`, `stacked:` are also available.

| Option | Notes |
|---|---|
| `title:` | rendered as `h3.card-title` in the header, unless a `header` slot is given |
| `size:` | `card-<size>` |
| `status:` | colour for a `.card-status-top` strip |
| `borderless:`, `stacked:` | booleans |
| `html:`, `header_html:`, `body_html:`, `footer_html:` | hooks |

Slots: `header`, `body`, `footer`.

### carousel

Builder style. Mandatory `id`.

```erb
<%= tabler_ui.carousel("my-carousel") do |carousel| %>
  <% carousel.item(image: image_path("slide1.jpg")) %>
  <% carousel.item(image: image_path("slide2.jpg"), active: true) %>
  <% carousel.item(image: image_path("slide3.jpg")) %>
<% end %>
```

Requires **exactly one** active slide — zero or more than one raises `ArgumentError`
naming the carousel's id (checked after the block runs, since Bootstrap fails silently
on both: zero shows a blank carousel, several show them stacked). The first slide added
is active by default when nothing is marked `active:` explicitly.

| Option | Notes |
|---|---|
| `fade:` | cross-fade instead of sliding |
| `indicators:` | `true` (default) / `false` / `:dot` / `:thumb` / `:vertical` |
| `controls:` | prev/next arrow buttons (default `true`) |
| `interval:` | ms between autoplay slides, or `false` to disable autoplay |
| `wrap:`, `keyboard:` | booleans, map to `data-bs-wrap` / `data-bs-keyboard` |
| `html:`, `inner_html:`, `indicators_html:`, `prev_html:`, `next_html:` | hooks |

`item(image:, caption:, caption_background:, active:, html:, caption_html:) { content }` —
a block replaces `image:` entirely.

### dark_mode_toggle

```erb
<%= tabler_ui.dark_mode_toggle %>
<%= tabler_ui.dark_mode_toggle size: :sm, title: "Switch theme" %>
```

Cycles light → dark → system, backed by `tabler-ui--dark-mode`. `size:` is
`:sm` / `:lg` (default 24px icons). `title:` defaults to the German "Theme
wechseln". Hooks: `html:` (outer div), `link_html:` (the `<a>`).

### datagrid

Builder style.

```erb
<%= tabler_ui.datagrid do |dg| %>
  <% dg.item "Name", content: "Ada Lovelace" %>
  <% dg.item "Bio" do %>Mathematician<% end %>
<% end %>
```

`items:` accepts pre-built `{ title:, content: }` hashes at construction, in
addition to (or instead of) the builder. Hooks: `html:`, and `item_html:` /
`title_html:` / `content_html:` (each a Hash or a `Proc` taking the item).

### dimmer

A plain server-side toggle, not a Stimulus controller — flip `active:` and re-render (e.g.
after a Turbo Stream update once a background job finishes).

```erb
<%= tabler_ui.dimmer active: @loading do |slots| %>
  <% slots.content { "Table rows go here" } %>
<% end %>
```

| Option | Notes |
|---|---|
| `active:` | shows the `.loader` and dims content to 10% opacity (default `false`) |
| `html:`, `loader_html:`, `content_html:` | hooks |

Slot: `content`.

### dropdown

Builder style.

```erb
<%= tabler_ui.dropdown label: "Actions", color: "danger", align: :end do |dropdown| %>
  <% dropdown.item "Edit", url: edit_path %>
  <% dropdown.item "Delete", url: delete_path, method: :delete %>
  <% dropdown.divider %>
  <% dropdown.header "More" %>
<% end %>
```

| Option | Notes |
|---|---|
| `label:` | toggle button text |
| `color:` | default `"primary"` |
| `align:` | `:start` (default) or `:end`. The strings `"start"`/`"end"` also work; anything else (including the old `"left"`/`"right"`) falls back to `:start` |
| `html:`, `toggle_html:`, `menu_html:` | hooks |

`item(title, url:, method:, active:, disabled:, icon:, html:)`, `divider`,
`header(title)`. Per-item `html:` may be a Hash or a `Proc` taking the item.

### empty

No-results / empty-state panel.

```erb
<%= tabler_ui.empty title: "No results found",
                     subtitle: "Try adjusting your search or filter." %>
<%= tabler_ui.empty image: "empty", title: "No results found" do |slots| %>
  <% slots.action { tabler_ui.button text: "New item", url: "#" } %>
<% end %>
```

| Option | Notes |
|---|---|
| `title:`, `subtitle:` | text parts |
| `header:` | large lead text (e.g. an error code) |
| `icon:` | Tabler icon name, rendered via `tabler_ui.icon` |
| `image:` | Tabler illustration name, rendered via `tabler_ui.illustration` |
| `bordered:` | `empty-bordered` |
| `html:`, `img_html:`, `icon_html:`, `header_html:`, `title_html:`, `subtitle_html:`, `action_html:` | hooks |

Slots: `img`, `icon`, `header`, `title`, `subtitle`, `action` — each overrides its
equivalent plain option.

### icon

```erb
<%= tabler_ui.icon icon: "user" %>
<%= tabler_ui.icon icon: "heart", filled: true, color: "danger", pulse: true %>
```

Reads a raw Tabler SVG off disk (gem assets first, then the host app's
`app/assets/icons/<outline|filled>/` as an override). Falls back to a bug icon
for an unknown name rather than raising.

| Option | Notes |
|---|---|
| `filled:` | outline (default) vs. filled variant |
| `color:` | *not* validated against `TablerUi::Color` — any string becomes `text-<color>` |
| `pulse:`, `tada:`, `rotate:` | animation classes |
| `size:` | `icon-<size>` |
| `title:` | `title="..."` attribute |
| `html:` | hook |

### illustration

```erb
<%= tabler_ui.illustration name: "empty" %>
<%= tabler_ui.illustration name: "empty", theme: "dark", size: :lg %>
```

Reads off disk the same way `icon` does (gem assets first, then the host's
`app/assets/illustrations/<theme>/`). Falls back to a "not found" SVG for an
unknown name.

| Option | Notes |
|---|---|
| `theme:` | `"light"` (default) or `"dark"` — **not** `variant:` |
| `size:` | named (`:xs` .. `:xxl`) or a raw pixel width; height scales proportionally |
| `html:` | hook |

### modal

Renders no trigger — wire your own `data-bs-toggle="modal" data-bs-target="#<id>"`,
exactly like Bootstrap's own docs. Mandatory `id`.

```erb
<button data-bs-toggle="modal" data-bs-target="#my-modal">Open</button>
<%= tabler_ui.modal "my-modal", title: "Confirm" do |slots| %>
  <% slots.body { "Are you sure?" } %>
  <% slots.footer { tabler_ui.button text: "Yes", color: "primary" } %>
<% end %>
```

| Option | Notes |
|---|---|
| `title:` | `h5.modal-title` in the header, unless a `header` slot is given |
| `size:` | `"sm"` / `"lg"` / `"xl"` / `"fullscreen"` |
| `centered:`, `scrollable:`, `blur:` | booleans |
| `status:` | colour for a `.modal-status` strip |
| `close_button:` | default `true` |
| `html:`, `dialog_html:`, `content_html:`, `header_html:`, `body_html:`, `footer_html:` | hooks |

Slots: `header`, `body`, `footer`.

### navbar

Builder style.

```erb
<%= tabler_ui.navbar brand: link_to("MyApp", root_path) do |navbar| %>
  <% navbar.left do |nav| %>
    <% nav.add "Dashboard", url: dashboard_path %>
    <% nav.dropdown "Admin", align: :end do |dd| %>
      <% dd.header "Manage" %>
      <% dd.item "Users", url: admin_users_path %>
      <% dd.divider %>
      <% dd.item "Settings", url: admin_settings_path, icon: "settings" %>
    <% end %>
  <% end %>
  <% navbar.right do |nav| %>
    <% nav.add "Logout", url: logout_path, method: :delete %>
  <% end %>
<% end %>
```

`brand:` (raw markup), `brand_autodark:` (default `true`). The block yields
the component; `left`/`right` each yield a `NavigationGroup` with `add(title,
url:, target:, method:, action:, subject:, active:, html:)`, `dropdown(title,
align:, html:) { |dd| ... }`, `dark_mode_toggle(**options)`, `divider`. The
dropdown proxy uses the **same** `item` / `divider` / `header` API as the
standalone `dropdown` component — there is no `.add` / `.add_divider` on it.
`active:` auto-detects via `current_page?` when omitted.

Hooks: `html:` (outer `header.navbar`), `brand_html:`, `toggler_html:`,
`menu_html:`, and per-item `html:` (Hash or Proc taking the item).

### offcanvas

Renders no trigger, same as `modal` — wire your own `data-bs-toggle="offcanvas"
data-bs-target="#<id>"`. Mandatory `id`.

```erb
<button data-bs-toggle="offcanvas" data-bs-target="#my-offcanvas">Open</button>
<%= tabler_ui.offcanvas "my-offcanvas", title: "Filters" do |slots| %>
  <% slots.body { "Filter form here" } %>
  <% slots.footer { tabler_ui.button text: "Apply", color: "primary" } %>
<% end %>
```

| Option | Notes |
|---|---|
| `title:` | `h5.offcanvas-title` in the header, unless a `header` slot is given |
| `position:` | `:start` (default) / `:end` / `:top` / `:bottom` |
| `narrow:` | fixed 20rem width |
| `backdrop:` | `false` or `:static`, maps to `data-bs-backdrop` |
| `scroll:` | allow body scrolling while open, maps to `data-bs-scroll` |
| `close_button:` | default `true` |
| `html:`, `header_html:`, `body_html:`, `footer_html:` | hooks |

Slots: `header`, `body`, `footer`.

### page_header

```erb
<%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview" do |slots| %>
  <% slots.buttons { tabler_ui.button text: "New report", color: "primary" } %>
<% end %>
```

| Option | Notes |
|---|---|
| `title:` | `h2.page-title` |
| `pretitle:` | small label above the title (**not** `subtitle:`) |
| `html:`, `title_html:`, `pretitle_html:`, `buttons_html:` | hooks |

Slot: `buttons` (right-aligned column).

### pagination

Never touches a collection, an ORM, or `params` — its entire input is two integers
(`current:`, `total:`) and a `url:` callable taking a page number.

```erb
<%= tabler_ui.pagination current: 3, total: 10, url: ->(n) { posts_path(page: n) } %>
```

Builder mode is also available for full manual control (`p.item`, `p.gap`, `p.prev`,
`p.next`), but mixing computed options (`current:`/`total:`) with builder calls raises
`ArgumentError` — the two are mutually exclusive.

```erb
<%= tabler_ui.pagination do |p| %>
  <% p.prev url: prev_path %>
  <% p.item 1, url: page_path(1) %>
  <% p.gap %>
  <% p.item 3, url: page_path(3), active: true %>
  <% p.next url: next_path %>
<% end %>
```

| Option | Notes |
|---|---|
| `current:`, `total:` | together switch on computed mode; `current:` given without `total:` raises |
| `window:` | pages shown either side of `current` in computed mode (default 2) |
| `size:` | `:sm` / `:lg` |
| `circle:`, `outline:` | booleans |
| `prev_label:`, `next_label:` | override the translated "Previous"/"Next" defaults |
| `html:`, `item_html:` | hooks (`item_html:` a Hash or `Proc` applied to every item) |

`total: 0` renders an empty list; out-of-range `current:` for any other total raises
`ArgumentError`.

### placeholder

Skeleton loading states.

```erb
<%= tabler_ui.placeholder type: :text, width: 9 %>
<%= tabler_ui.placeholder type: :text, lines: [10, 11, 8] %>
<%= tabler_ui.placeholder type: :avatar %>
<%= tabler_ui.placeholder type: :image, ratio: "21x9" %>
<%= tabler_ui.placeholder type: :button, width: 4, color: "primary" %>
<%= tabler_ui.placeholder type: :card, animation: :glow %>
```

| Option | Notes |
|---|---|
| `type:` | `:text` (default) / `:avatar` / `:image` / `:button` / `:card` / `:list`; anything else renders a bare fallback `span.placeholder` |
| `width:` | column width (1-12), text/button |
| `lines:` | array of column widths, multi-line `:text` |
| `size:` | `xs sm lg xl` |
| `animation:` | `:glow` / `:wave` |
| `ratio:` | `1x1 4x3 16x9 21x9`, falls back to `21x9` |
| `color:` | `:button` type only |
| `rounded:` | `:avatar`, default `true` |
| `show_image:`, `show_button:` | `:card` type, both default `true` |
| `html:` | root of whichever type rendered |
| `body_html:` | `:card` type's inner `.card-body` |

### progress

```erb
<%= tabler_ui.progress percent: 60, striped: true, animated: true %>
<%= tabler_ui.progress percent: 82, color: "auto" %>
<%= tabler_ui.progress percent: 60, label: "Uploading", show_percent: true %>
```

| Option | Notes |
|---|---|
| `percent:` | clamped to 0..100, default 0 |
| `color:` | default `"primary"`; the magic value `"auto"` bypasses validation and picks success/warning/danger from the percentage (>=90 danger, >=75 warning) |
| `height:` | CSS height, e.g. `"4px"` |
| `label:`, `show_percent:` | label row above the bar |
| `size:` | `:sm` / `:lg` |
| `striped:`, `animated:` | booleans |
| `html:`, `bar_html:`, `label_html:` | hooks |

### rating

Renders a `<select>`, replaced client-side by star-rating.js via
`tabler-ui--rating`.

```erb
<%= tabler_ui.rating %>
<%= tabler_ui.rating choices: [{ value: 1, label: "Bad" }, { value: 2, label: "Great" }], max_stars: 2, color: "yellow" %>
```

| Option | Notes |
|---|---|
| `id:`, `name:` | defaults: generated id, `"rating"` |
| `value:` | selected value |
| `choices:` | array of `{ value:, label: }`; default is an "Excellent".."Terrible" scale sized to `max_stars:` (**not** `options:`) |
| `required:`, `disabled:` | default `false` |
| `size:` | forwarded to star-rating.js |
| `color:` | validated |
| `tooltip:`, `clearable:` | default `true` |
| `max_stars:` | default 5 |
| `html:` | hook |

### ribbon

A small label pinned to a corner of a `position: relative` parent (typically a card).

```erb
<%= tabler_ui.ribbon text: "New", color: "blue" %>
<%= tabler_ui.ribbon text: "Sale", color: "red", position: :bottom, align: :start %>
```

| Option | Notes |
|---|---|
| `text:` | label; a block (via the `body` slot) overrides it for rich content |
| `color:` | validated, rendered as `bg-<color>` |
| `position:` | `:top` (default) / `:bottom` |
| `align:` | `:start` / `:end` (default) |
| `bookmark:` | `ribbon-bookmark` shape |
| `icon:` | Tabler icon name |
| `html:` | hook |

Slot: `body`.

### settings_page

Builder style. Mandatory `id`.

```erb
<%= tabler_ui.settings_page "my-settings", title: "Settings" do |sp| %>
  <% sp.item "General", icon: "settings" do %>General settings<% end %>
  <% sp.item "Security", icon: "shield", active: true do %>Security settings<% end %>
<% end %>
```

`title:` defaults to `"Settings"`. `item(title, icon:, active:, html:) { content }`
— the first item added is active by default. Hooks: `html:` (outer `.card`),
`sidebar_html:`, `content_html:`, per-item `html:`.

### spinner

```erb
<%= tabler_ui.spinner %>
<%= tabler_ui.spinner type: :grow, size: "sm", color: "blue" %>
```

| Option | Notes |
|---|---|
| `type:` | `:border` (default) / `:grow` |
| `size:` | `"sm"` |
| `color:` | validated, rendered as `text-<color>` (the spinner's border colour is `currentcolor`) |
| `label:` | visually-hidden text, `role="status"`, defaults to a translated "Loading..." |
| `html:` | hook |

### stat_card

```erb
<%= tabler_ui.stat_card label: "Sales", value: "456", icon: "shopping-cart", trend: 12 %>
<%= tabler_ui.stat_card label: "New clients", value: "18", trend: -8, description: "vs. last month", url: "/clients" %>
```

| Option | Notes |
|---|---|
| `label:`, `value:` | header text / headline metric |
| `icon:` | colored icon box |
| `trend:` | percentage; positive renders green with an up arrow, negative red with a down arrow, zero/nil renders nothing |
| `description:` | small text under the value |
| `color:` | icon box colour, default `"primary"` |
| `url:` | renders a "Details" link |
| `html:`, `body_html:`, `value_html:`, `link_html:` | hooks |

### status

```erb
<%= tabler_ui.status text: "Online", color: "green", dot: true %>
<%= tabler_ui.status color: "green", dot: true, standalone: true %>
<%= tabler_ui.status color: "red", indicator: true, animated: true %>
```

| Option | Notes |
|---|---|
| `text:` | optional for standalone dots/indicators |
| `color:` | default `"blue"` |
| `dot:` | dot in front of the text |
| `animated:` | animates the dot/indicator |
| `light:` | `status-lite` variant (**not** `lite:`) |
| `standalone:` | dot only, no text |
| `indicator:` | 3-circle status indicator style |
| `html:`, `dot_html:` | hooks (`dot_html:` only when a dot renders alongside text) |

### steps

Builder style.

```erb
<%= tabler_ui.steps(current: 2) do |steps| %>
  <% steps.item("Account") %>
  <% steps.item("Profile") %>
  <% steps.item("Confirm") %>
<% end %>
```

Takes a single 1-based `current:` index for the whole component rather than a
per-item `active:` flag — the CSS's dimming rule only makes sense with one active step.
Out-of-range `current:` raises `ArgumentError` once every item is known (checked after
the block runs).

| Option | Notes |
|---|---|
| `current:` | 1-based index of the active step (default 1) |
| `vertical:` | `steps-vertical` |
| `counter:` | numbered dots instead of plain dots |
| `color:` | Tabler palette only (`TablerUi::Color::TABLER`) — Bootstrap semantic names raise |
| `light:` | `steps-<color>-lt`; only has an effect together with `color:` |
| `html:` | hook |

`item(title, url:, html:)` — `url:` renders an `<a>` (letting earlier steps link back), a
plain `<li>` otherwise.

### table

```erb
<%= tabler_ui.table columns: [{ label: "Name", value: ->(row) { row[:name] } }], data: @users, striped: true %>
<%= tabler_ui.table columns: columns, data: rows,
                     row_html: ->(row) { row.overdue? ? { class: "table-danger" } : {} } %>
```

There is no builder-style `table.column "Name", :name, sortable: true` API —
columns are a plain array of `{ label:, value:, class: }` hashes, `value:` a
callable invoked per row.

| Option | Notes |
|---|---|
| `columns:` | each `{ label:, value: ->(row) { ... }, class: }` |
| `data:` | row collection, default `[]` |
| `striped:`, `hover:`, `bordered:`, `sm:`, `nowrap:`, `vcenter:` | table modifier classes |
| `card:` | wraps in `.card` / `.table-responsive` (default `true`); set `false` to nest inside an existing card |
| `html:` | outermost element — `.card`, or `.table-responsive` when `card: false` |
| `table_html:`, `thead_html:`, `tbody_html:` | hooks |
| `row_html:` | Hash (every row) or Proc taking the row |

### tabs

Builder style. Mandatory `id`.

```erb
<%= tabler_ui.tabs "my-tabs", style: :pills do |tabs| %>
  <% tabs.tab "Inbox", icon: "mail", badge: { text: "3", color: "red" } do %>...<% end %>
  <% tabs.tab "Sent" do %>...<% end %>
<% end %>
```

| Option | Notes |
|---|---|
| `style:` | `:tabs` (default) / `:pills` / `:card` / `:underline` |
| `html:`, `nav_html:`, `content_html:` | hooks |

`tab(title, icon:, badge:, active:, html:) { content }` — first tab active by
default. `badge:` is a String (rendered with the badge component's own default
colour) or a Hash forwarded to `tabler_ui.badge`, e.g. `{ text: "3", color:
"red" }` (**not** `badge_color:`).

### timeline

Builder style.

```erb
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

An item's card content is entirely up to the caller — nest a `tabler_ui.card` yourself if
you want one; the component does not bake card structure into `.timeline-event-card`.

| Option | Notes |
|---|---|
| `simple:` | hides the icon column entirely, drops the card's left margin |
| `html:`, `item_html:` | hooks |

`item(icon:, color:, icon_html:, card_html:) { content }` — no mandatory positional
argument; content comes entirely from the block.

### toast

Renders no trigger — if you want click-to-show behaviour, put
`data-bs-toggle="toast" data-bs-target="#<id>"` on your own element.

```erb
<%= tabler_ui.toast title: "Success", color: "success" do |slots| %>
  <% slots.body { "Changes saved." } %>
<% end %>
```

| Option | Notes |
|---|---|
| `title:` | `strong.me-auto` in the header, unless a `header` slot is given |
| `color:` | validated (Tabler palette + Bootstrap semantic names both work here) |
| `autohide:`, `delay:` | map to `data-bs-autohide` / `data-bs-delay`; only rendered when given explicitly |
| `close_button:` | default `true` |
| `position:` | e.g. `"top-right"` — wraps the toast in a fixed `.toast-container`; omitted by default so several toasts can share one caller-provided container |
| `html:`, `header_html:`, `body_html:`, `container_html:` | hooks |

Slots: `header`, `body`.

## Forms

```erb
<%= tabler_form_with model: @user do |f| %>
  <%= f.input :name %>
  <%= f.input :bio, as: :text %>
  <%= f.input :role, as: :select, collection: %w[admin member] %>
  <%= f.error_notification %>
  <%= f.submit "Save" %>
<% end %>

<%= tabler_ui_form_for @user do |f| %>
  <%= f.input :name %>
<% end %>
```

Both helpers set `builder: TablerUi::FormBuilder`; otherwise their options are
identical to `form_with`/`form_for`.

`f.input(method, options = {})` picks a renderer from the column type, unless
overridden with `as:`. `:date`, `:integer`, `:decimal`, `:float`, `:datetime`
and `:time` all resolve through the same string dispatch, which picks the
right native input (`number`, `datetime-local`, `time`, a datepicker-wired
text field for `:date`); an unrecognised column type raises `ArgumentError`
naming the field, not a bare `NoMethodError`. `:decimal`/`:float` get
`step: "any"` unless overridden via `input_html:`.

Explicit `as:` values: `:string`, `:text`, `:boolean`, `:select`,
`:grouped_select`, `:file`, `:radio_buttons`, `:check_boxes`, `:date_picker`,
`:color`, `:imagecheck`, `:input_group`, `:floating`. Also `f.toggle_button`
and `f.toggle_switch` (clickable-button / switch-styled booleans),
`f.association` (auto-detects `belongs_to` → select, `has_many` → checkboxes),
and `f.input_field` (a naked input with no wrapper/label).

Common options: `label:` (`false` to suppress), `label_description:`,
`required:`, `hint:`, `collection:`, `value_method:`, `text_method:`,
`input_html:` (merged onto the field the same way `html:` merges everywhere
else), `label_html:`. A field with a model error automatically gets
`is-invalid` plus an `.invalid-feedback` message; `f.error_notification` renders
every error as a Tabler alert.

## Stimulus controllers

14 controllers ship under `controllers/tabler_ui/`, self-registered by
`tabler_ui.js` against `window.Stimulus`:

| Controller | Identifier | Purpose |
|---|---|---|
| `alert_controller.js` | `tabler-ui--alert` | dismissible alerts (Bootstrap `Alert`) |
| `carousel_controller.js` | `tabler-ui--carousel` | drives `carousel` (Bootstrap `Carousel`) |
| `chart_controller.js` | `tabler-ui--chart` | ApexCharts init from `data-*-value` attrs |
| `collapse_controller.js` | `tabler-ui--collapse` | navbar mobile menu and `accordion` panes (Bootstrap `Collapse`) |
| `dark_mode_controller.js` | `tabler-ui--dark-mode` | light/dark/system theme cycling, `localStorage`-backed |
| `datepicker_controller.js` | `tabler-ui--datepicker` | wraps `vanillajs-datepicker` (CDN-pinned) |
| `dropdown_menu_controller.js` | `tabler-ui--dropdown-menu` | dropdown open/close (Bootstrap `Dropdown`), used by both `dropdown` and `navbar` |
| `filter_controller.js` | `tabler-ui--filter` | debounced auto-submit for filter forms |
| `modal_controller.js` | `tabler-ui--modal` | drives `modal` (Bootstrap `Modal`) |
| `offcanvas_controller.js` | `tabler-ui--offcanvas` | drives `offcanvas` (Bootstrap `Offcanvas`) |
| `rating_controller.js` | `tabler-ui--rating` | wraps `star-rating.js` |
| `tab_controller.js` | `tabler-ui--tab` | tab/list-group switching (Bootstrap `Tab`), used by `tabs` and `settings_page` |
| `toast_controller.js` | `tabler-ui--toast` | drives `toast` (Bootstrap `Toast`) |
| `toggle_button_controller.js` | `tabler-ui--toggle-button` | `FormBuilder#toggle_button`'s filled/outline state |

Eight of these (`alert`, `carousel`, `collapse`, `dropdown_menu`, `modal`, `offcanvas`, `tab`,
`toast`) wrap a Bootstrap JS object with matching `connect()`/`disconnect()` lifecycle so Turbo
doesn't leak instances across reconnects. Each *adopts* an existing Bootstrap instance via
`getOrCreateInstance` rather than constructing a second one over whatever `tabler.js`'s own
bundle already created at import time, and only disposes an instance it created itself — this
fixed a real bug where every one of these controllers used to instantiate its own competing
Bootstrap object. They're wired onto the markup automatically by the components above, no
manual `data-controller` needed except for `tabler-ui--chart` and `tabler-ui--filter`.

## Upgrading from 0.2.x

Every renamed or removed option below is enforced, not just documented: passing
the old name is silently ignored (falls back to the component's default)
rather than raising, so a missed rename in an upgrading app fails quietly —
check your views against this table rather than trusting things "still work".

| Component | Old | New |
|---|---|---|
| alert, button, dropdown (as `button_variant:`), placeholder, rating | `variant:` | `color:` |
| illustration | `variant:` | `theme:` |
| status | `lite:` | `light:` |
| alert | `message:` | `text:` |
| alert | `link:` | `url:` |
| button | `to:` | dropped — use `url:` |
| page_header | `ph.pretitle = ...` / `subtitle:` | `pretitle:` option |
| page_header | `ph.title = ...` | `title:` option |
| rating | `options:` | `choices:` |
| tabs | `badge_color:` | `badge: { color: ... }` |
| navbar dropdown proxy | `.add` / `.add_divider` | `.item` / `.divider` (same API as the standalone `dropdown` component) |
| dropdown, navbar | `align: "left"` / `"right"` | `align: :start` / `:end` (`"start"`/`"end"` strings also accepted) |
| all builder methods (`dropdown.item`, `navbar.add`, `tabs.tab`, `settings_page.item`, `datagrid.item`) | keyword title, e.g. `item(title: "Edit")` | positional, e.g. `item("Edit")` — the old form now raises `ArgumentError` instead of silently rendering a Hash |
| every component | `custom_class:` / `class:` | `html: { class: "..." }` (or `<part>_html: { class: "..." }`) — appends rather than replaces |
| card block | `do |card, slots|` | `do |slots|` — the dispatcher yields exactly one argument |
| table | `table.column "Name", :name, sortable: true` builder | `columns: [{ label:, value:, class: }]` array, no sorting support |

Every row above was checked against `app/components/tabler_ui/*/component.rb`
and its spec — most have an explicit regression test asserting the old name is
now inert (e.g. `alert_spec.rb`: `"no longer accepts variant: -- passing it has
no effect"`).

`badge`, `card` (its `status:` strip colour), `progress` and `stat_card` also
take `color:` today, consistent with every other component — but their specs
carry no explicit "no longer accepts `variant:`" regression test, so that
particular rename isn't independently confirmed for those four the way it is
for the row above.
