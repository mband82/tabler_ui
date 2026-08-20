# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `table` takes `sort:`, `sort_url:` and `sort_reset:`, plus a per-column `sort:` key marking a
  column sortable. The component renders the header links and the asc/desc state; working out the
  order stays with the caller, as it already does for the rows themselves.
- `table` takes `filter:`, a search/filter toolbar rendered above the table. Either declarative
  (`fields:` of `:search`/`:text`/`:select`/`:date`) or a `slots.filter` block supplying the form
  contents. A `:get` form auto-submits through the `tabler-ui--filter` Stimulus controller; a
  `:post` form gets an Apply button. `hidden:` carries the current sort across a filter submit.
- `table` and `pagination` take `frame:`, emitting the markup for Turbo Frame navigation so
  sorting, filtering and paging update the table without a page reload. `table` renders the
  `<turbo-frame>` around the table itself and points the filter form at it from outside, so the
  debounced search input is never re-rendered mid-typing; `pagination` only targets the frame.
  Opt-in and markup-only — the gem takes no `turbo-rails` dependency.
- `table` takes a `footer` slot, rendering a `.card-footer` inside the card. It sits inside the
  turbo-frame, so a pager or a row count placed there re-renders with the table instead of going
  stale. This is the opposite of the filter toolbar, which stays outside the frame so the search
  input survives typing.
- A `:search`/`:text` filter field takes `button:`, rendering the input in an input group with an
  attached submit button.
- `filter:` takes `min_chars:`, below which the auto-submitting form submits with the search value
  blanked — so the table returns to unfiltered results, the URL follows, and a hint appears under
  the field. Clearing the field always submits, so a user cannot get stuck filtered. It applies
  only to an auto-submitting form on a framed table, and is silently inert otherwise.
- New HTML hooks: `sort_html:`, `filter_html:`, `filter_form_html:`, `filter_reset_html:`,
  `filter_button_html:`, `filter_hint_html:`, `frame_html:` and `footer_html:` on `table`, and
  `link_html:` on `pagination`. `link_html:` and `filter_reset_html:` close rule 5 gaps on elements
  that previously had no hook at all.

### Changed

- `filter: { auto: }` now defaults to true only for a `:get` form on a table that has a `frame:`,
  and false otherwise. Auto-submitting without a frame meant every debounced submit was a full
  navigation, so the search field lost focus and the page jumped to the top mid-typing. An explicit
  `auto: true` still opts in, for hosts driving the form themselves.

### Fixed

- `navbar.css` was in the engine's precompile list but missing from the stylesheet manifest, so it
  was compiled and served but never actually loaded. Its alignment fixes now apply, which makes nav
  items reach the full navbar height and puts Tabler's active indicator on the bottom edge.
- `pagination` emitted `page-prev`/`page-next` on every prev/next item. Tabler gives those classes
  `flex: 0 0 50%` for its article-style pager, where the two are the only items, so combining them
  with page numbers overflowed the container and pushed Next outside it. They are now emitted only
  for a pure prev/next pager.

## [0.5.0] - 2026-08-17

Closes every gap an audit of all 33 components against the bundled Tabler v1.4.0 stylesheet
rated XS or S -- 42 features the CSS supported that the Ruby API could not reach. Three of
those turned out to be bugs rather than gaps, and fixing them changes rendered output.

### Fixed

- `card`'s `status:` option never worked. `card-status-top` is a bare selector setting
  `position: absolute; height: 2px`, and it was being applied to the `.card` element itself,
  collapsing the whole card into a 2px sliver. The strip is now a dedicated empty child element,
  which is what Tabler's markup expects.
- `tabs` with `style: :underline` emitted `nav-tabs nav-tabs-alt`. `nav-tabs-alt` does not exist
  anywhere in the bundled stylesheet, so the style rendered as a plain tab bar. It now emits
  `nav-underline`, replacing `nav-tabs` rather than adding to it.
- `button` with `shape: "pill"` emitted Bootstrap's `rounded-pill`, which only sets a border
  radius. It now emits Tabler's `btn-pill`, which also widens the horizontal padding and carries
  the padding fix for icon-only pill buttons.

### Added

- Two components, taking the gem from 33 to 35: `badge_list` (`badges-list`) and `card_group`.
- `alert`: `minor:`, `link_style:` (`:link` / `:action`), and `color: "muted"`.
- `avatar`: `cover:`, and an `overlay` slot for nesting a status dot or brand chip. Not supported
  on generated identicon avatars, which raise -- an HTML overlay cannot be nested in `<svg>`.
- `badge`: `dot:` and `icon_only:`.
- `button`: `loading:`, `floating:`, `animate_icon:`, `ghost:`, and the brand colour palette
  (`facebook`, `github`, `x`, ... plus `muted`), accepted on buttons only.
- `card`: `status_position:` (`"top"` / `"start"` / `"bottom"`) and a `status_html:` hook.
- `carousel`: `dark:`.
- `dropdown`: `dark:`, `scrollable:`, `arrow:`, `direction:` (`"up"`, `"end"`, `"start"`,
  `"up-center"`, `"down-center"`) and `align_breakpoint:`.
- `modal`: `full_width:`, and `size:` now accepts `fullscreen-<breakpoint>-down`.
- `navbar`: `expand:`, `dark:`, `transparent:`, `overlap:`, `nav_scroll:`.
- `offcanvas`: `expand:`.
- `page_header`: `border:`, `title_size:`, `subtitle:` (rendered below the title, distinct from
  `pretitle:`) and a `subtitle_html:` hook.
- `progress`: `indeterminate:` and `separated:`.
- `table`: `responsive:` (`true` / breakpoint / `false`) and `mobile:`, which stacks rows as cards
  and derives each cell's `data-label` from its column heading.
- `tabs`: `style: :bordered`, `style: :segmented` (with `vertical:`), `fill:` and `justified:`.
- `TablerUi::Breakpoint`, a shared `sm`/`md`/`lg`/`xl`/`xxl` vocabulary that raises on unknown
  values, mirroring `TablerUi::Color` and `TablerUi::Align`.

### Changed

- `TablerUi::Color.validate!` takes an optional `extra:` keyword listing additional values valid
  at that call site. `Color::ALL` is deliberately unchanged, so brand names and `muted` stay
  invalid for components that have no matching CSS -- `bg-facebook` does not exist.
- `dropdown` item icons now carry Tabler's `dropdown-item-icon` class instead of an ad-hoc `me-1`
  margin utility.
- `page_header` accepts `subtitle:` again. It was removed in 0.4.0 as a mislabelled alias for
  `pretitle:`; it now means something different -- text *below* the title.

### Known limitation

- `progress`'s `separated:` emits the correct class but has no visible effect yet. The CSS draws a
  separating ring around each bar, which only shows once several bars share one track. That is
  `progress-stacked`, which is not implemented.

## [0.4.0] - 2026-08-17

No breaking changes in this release.

### Added

- 13 new components, taking the gem from 20 to 33: `spinner`, `ribbon`, `dimmer`, `empty`,
  `breadcrumb`, `timeline`, `steps`, `modal`, `offcanvas`, `toast`, `accordion`, `carousel`,
  `pagination`.
- `config/locales/en.yml`, routing every user-visible default string the gem renders through
  I18n under a `tabler_ui` namespace; auto-loaded by the engine, and overridable by a host app
  the normal Rails way.
- Four Stimulus controllers for the new overlay/carousel components -- `modal_controller`,
  `offcanvas_controller`, `toast_controller`, `carousel_controller` -- bringing the total to 14
  (up from 10). `accordion` reuses the existing `collapse_controller` rather than adding a
  redundant one of its own.
- A dispatcher `validate!` hook: a component class may define it, and the dispatcher calls it
  once a builder block has finished running, before rendering -- used by `steps` (`current:`
  range), `carousel` (exactly one active slide) and `accordion` (single-open constraint).
- A dispatcher guard that raises `ArgumentError` when a slot-style component's block writes
  content but sets no slots, instead of silently rendering nothing.
- A `showcase/` app (dev-only, excluded from the packaged gem) rendering every component
  alongside its source snippet -- `cd showcase && bin/rails server -p 3561`.
- `sprockets-rails ~> 3.5` declared as a gem dependency -- the CSS asset manifest
  (`app/assets/stylesheets/tabler_ui.css`) has always required Sprockets; Propshaft, Rails 8's
  default pipeline, cannot process it.

### Fixed

- **FormBuilder**: `as: :input_group` raised `ArgumentError` for every caller -- the private
  method backing it was named `input_group`, missing the `_input` suffix the dispatcher's
  string-based method lookup requires. Renamed to `input_group_input`.
- **FormBuilder**: automatic column-type detection (native `number`/`datetime-local`/`time`
  inputs, the `:date` datepicker) only worked against ActiveRecord's instance-level
  `type_for_attribute`/`column_for_attribute`. A plain `ActiveModel::Attributes` object exposes
  those at the class level instead, so every field on a non-ActiveRecord model silently fell
  back to a text input; `object_type_for_method` now also checks the class-level
  `attribute_types`.
- **Stimulus**: `alert_controller`, `collapse_controller`, `dropdown_menu_controller` and
  `tab_controller` each constructed their own Bootstrap JS instance with `new Bootstrap.X(...)`,
  competing with the instance `tabler.js`'s own bundle already creates at import time. All four
  now adopt the existing instance via `getOrCreateInstance` and dispose only an instance they
  created themselves.
- Four previously-hardcoded German UI strings (the form error heading, the illustration
  not-found/unknown text, the dark mode toggle's title) now render in English by default and are
  translatable like every other string added this release.

### Changed

- `config/locales/en.yml` gained keys for every new component's default strings (`pagination`,
  `carousel`, `breadcrumb`, `dimmer`, `offcanvas`, `modal`, `toast`, `spinner`, `steps`)
  alongside the four moved out of hardcoded German.

## [0.3.0] - 2026-08-17

All 20 components were rewritten across eight commits: a shared foundation
(`TablerUi::Base`, HTML-hook merging, colour validation), then every
component converted to the options-hash convention, then Stimulus/form
builder fixes. See `CLAUDE.md` rules 4-7 for the conventions behind this.

### Breaking changes

- **All components**: component classes must now `include TablerUi::Base`;
  the dispatcher raises `ArgumentError` if a class exists but doesn't.
- **All components**: unknown `color:`/`status:` values now raise
  `ArgumentError` instead of silently falling back to a default.
- **All components**: `custom_class:` and `class:` are gone. Use `html:`
  (single-element components) or `<part>_html:` (multi-part components),
  e.g. `header_html:`, `body_html:`, `footer_html:`.
- **Builder methods** (`item`, `tab`, `add`, `dropdown`, `header`): title is
  now the mandatory positional argument -- `item("General")`, not
  `item(title: "General")`. Passing the old keyword form now raises instead
  of silently rendering wrong content.
- **alert**: `variant:` -> `color:`; `message:` -> `text:`; `link:` ->
  `url:`; the `content` accessor is gone (use `text:` or the `body` slot).
- **badge**: `variant:` -> `color:`.
- **button**: `variant:` -> `color:`; `to:` is gone, `url:` is canonical.
- **dropdown**: `variant:`/`button_variant:` -> `color:`; `align:` now takes
  `:start`/`:end` (`"left"`/`"right"` silently fall back to `:start`).
- **illustration**: `variant:` -> `theme:` (it always selected the asset
  folder, "light"/"dark", never a colour).
- **navbar**: nested dropdowns now use the same `.item`/`.divider`/`.header`
  API as the standalone dropdown, replacing `.add`/`.add_divider`; `align:`
  takes `:start`/`:end` like dropdown.
- **page_header**: `subtitle:` -> `pretitle:`, matching the `.page-pretitle`
  class it renders.
- **placeholder**: `variant:` -> `color:`.
- **rating**: `options:` -> `choices:`; `variant:` -> `color:`.
- **status**: `lite:` -> `light:`.
- **tabs**: `badge_color:` is gone -- pass `badge: { color: "red" }` (or a
  plain string for the badge's own default colour).
- **Stimulus**: the hand-rolled `tabler-ui--dropdown` controller is gone,
  replaced by `tabler-ui--dropdown-menu`, a thin lifecycle wrapper around
  Bootstrap's own dropdown JS.

### Fixed

- **card**: every card rendered `class="card OpenStruct"` and discarded any
  class the caller passed in.
- **avatar**: reseeded Ruby's *global* RNG via `srand` on every render,
  perturbing unrelated `rand` calls elsewhere in the process; also defined
  `rand_color` onto the shared view class from inside its own template on
  every render. Both are now scoped correctly.
- **rating**: could not render at all with its own defaults (choices were
  computed before `max_stars` was set).
- **status**: silently rendered unknown colours as blue.
- **progress**: percent clamping returned the wrong type at the boundaries.
- **icon**: appended caller classes to every nested `<svg>` element via a
  global `gsub`, not just the root; now scoped to the root tag only.
- **icon, illustration**: interpolated unsanitised names into a filesystem
  path; names containing `/` or `..` are now rejected outright.
- **JavaScript**: `chart_controller` was pinned and precompiled but never
  registered with Stimulus; `toggle_button_controller` was registered but
  never added to the precompile list. Both now work.
- **datepicker controller**: leaked a datepicker instance on every Turbo
  navigation instead of destroying it on `disconnect()`.
- **filter controller**: shipped `console.log` debug output and never
  cleared its debounce timer on `disconnect()`.
- **FormBuilder**: `:decimal`, `:float`, `:datetime` and `:time` columns
  raised `NoMethodError`; all four now render (numeric field with
  `step: "any"`, native `datetime-local`/`time` inputs).

### Added

- Rule-5 `html:`/`<part>_html:` hooks across all 20 components -- ten
  (avatar, badge, button, datagrid, navbar, page_header, placeholder,
  progress, stat_card, table) had no class hook at all before this release.
- **avatar**: `image:` option (previously documented, never implemented).
- **badge**: `outline:` option (`badge-outline`).
- **card**: `status:`, `borderless:`, `stacked:` options.
- **progress**: `striped:`, `animated:` options.
- **table**: `bordered`, `sm`, `nowrap`, `vcenter` options; `card: false` to
  opt out of the wrapping `.card`; `row_html:` now also accepts a callable
  for per-row conditional styling.
- Four Stimulus controllers wrapping Bootstrap's own JS: `tab_controller`,
  `collapse_controller`, `dropdown_menu_controller`, `alert_controller`.
- ApexCharts 5.4.0 integration (453 KB JS, 14.5 KB CSS) and its
  `chart_controller`, now fully wired (registered + precompiled).
- RSpec + Combustion test suite -- the gem had no tests before this release.

### Changed

- The component dispatcher (`lib/tabler_ui/ui.rb`) selects modern vs. legacy
  behaviour from a `TablerUi::Base` marker and `builder_style!` declaration,
  not reflection/duck-typing on method names.
- All seven bare partials (`button`, `card`, `page_header`, `table`,
  `stat_card`, `progress`, `avatar`) became component classes.
- Bootstrap's own JS (tabs, collapse, dropdowns, alerts) is now driven
  through thin Stimulus lifecycle wrappers instead of raw `data-bs-*`
  markup alone.

## [0.2.0] - 2026-02-03

### Updated
- Upgraded Tabler UI Framework from v1.2.0 to v1.4.0
- Core CSS: 648 KB → 619 KB (optimized)
- Core JavaScript: v1.4.0 (202 KB)
- Star Rating JS: v4.3.0 (15 KB, unchanged version but updated build)
- Updated CSS source maps

### Added
- Flags Add-on Module (19 KB CSS + 260 flag SVGs)
- Tabler Theme JS (1.4 KB) for enhanced dark mode support
- Asset paths for SVG images (flags)

### Notes
- Flags module is optional, activate with: `*= require tabler_ui/addons/tabler-flags`
- tabler-theme.js provides enhanced dark mode support complementary to existing dark_mode_controller.js

### Breaking Changes
- Verify custom CSS overrides against new v1.4.0 variables
- Test all components with updated Tabler UI v1.4.0

## [0.1.0] - 2026-02-03

### Added
- Initial gem structure with Rails Engine
- Core UI dispatcher with method_missing pattern
- Tabler UI helper for view access
- Navbar component with dropdown support
- Page Header component
- Avatar component with initials and image support
- Table component with sortable columns
- Button component with variants, sizes, and states
- Card component with slot support
- Dropdown component with items, dividers, and headers
- Bundled Tabler UI CSS (v1.2.0)
- Bundled Tabler UI JavaScript (v1.2.0)
- Stimulus controller for custom dropdown behavior
- Comprehensive README documentation
- Asset pipeline integration for Rails 8+
- Importmap configuration for JavaScript modules

## [0.1.0] - TBD

### Initial Release
- First version of the gem
- Core components extracted from WBB.NET project
- Full Tabler UI framework integration
