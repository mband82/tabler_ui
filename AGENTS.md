# AGENTS.md

This file mirrors `CLAUDE.md`'s project conventions for AI coding agents other than
Claude Code (Cursor, Codex CLI, Copilot, aider, and similar tools). `CLAUDE.md` is the
authoritative source and additionally covers Claude-Code-specific process — its own
subagent delegation workflow — that doesn't apply generally and is omitted here.

Keep the two files in sync: a change to one of the shared rules below (everything in
`CLAUDE.md` except its subagent-delegation rule) should be mirrored in the other.

Working rules for this project. Read before starting any task.

## Clean up shells

Background shells are cleaned up as soon as they are no longer needed — they do not
get left running to the end of the session.

- Whoever starts a background shell kills it when its work is done. Clean up your own,
  and anything left running from an earlier step of the same task.
- Before reporting a task complete, check for and kill leftover background shells.
- Long-running processes started for a check (servers, watchers, `tail -f`) are stopped
  as soon as the check is answered.
- Do not accumulate idle shells across turns "in case they are needed again".

## Commit messages stay brief

One short line per change. No essays.

- A commit touching one thing gets one line. Imperative mood, e.g.
  `Add toggle_switch helper for switch inputs`.
- A commit touching several things gets one short bullet per change, nothing more:

  ```
  Fix numeric form inputs

  - Add decimal/float handling to FormBuilder#input
  - Register chart_controller in tabler_ui.js
  ```
- No paragraphs explaining rationale, no restating what the diff already shows.
  If the why genuinely matters, it belongs in the code as a comment or in this file.
- **No `Co-Authored-By` trailer.** Commits end at the last bullet.
- Commit only when asked.

## Rails-conventional signatures

Mandatory arguments are explicit. Optional arguments live in an options hash.

- **Mandatory** -> a positional parameter.
- **Optional** -> keys in a trailing `options = {}` hash. Never a long tail of
  keyword args with defaults.

```ruby
# Good
def initialize(icon, options = {})
  @icon    = icon
  @filled  = options[:filled]
  @color   = options[:color]
  @custom_class = options[:class]
end

# A component with no mandatory arguments:
def initialize(options = {})
end

# Not this
def initialize(icon:, filled: false, color: nil, pulse: false, size: nil, class: nil)
```

- `def initialize(icon:, options = {})` is a **SyntaxError** — an optional positional
  parameter cannot follow a keyword parameter. Verified on Ruby 3.4.9. That shape used
  to be the "Good" example in this rule; it never ran. Use the positional form above.
- Callers still use keyword syntax at the call site — `tabler_ui.icon icon: "user", size: "lg"`.
  The dispatcher in `lib/tabler_ui/ui.rb` maps those keywords onto the constructor's
  positional parameters.
- Read optional values with `options[:key]`, or `options.fetch(:key, default)` when a
  default is needed.
- This removes the `class:`/`Object#class` collision for free — inside an options hash
  `:class` is an ordinary key, so `binding.local_variable_get(:class)` is no longer
  needed in new code.
- Existing components mostly use the old long-keyword form. Convert them when you are
  already editing one; do not do a separate sweep unless asked.
- Any Ruby snippet added to this file gets checked with `ruby -c` before being written
  down. That check is exactly what would have caught the SyntaxError above.

## HTML hooks on every subcomponent

Every meaningful HTML element a component emits must be customizable from the outside,
in the style of Rails' `tag` helpers.

- A single-element component takes `html:` in its options hash.
- A multi-part component takes one key per part, named `<part>_html:`. A modal exposes
  `dialog_html:`, `header_html:`, `body_html:`, `footer_html:`. A form field exposes
  `input_html:` (already the case in `FormBuilder`) and `label_html:`.
- The hash is passed through to the tag helper, so callers can set `class`, `data`,
  `aria-*`, `id`, anything.
- **Merge, do not replace.** A caller's `class` is appended to the component's own
  classes; other attributes overwrite. `FormBuilder#merge_input_options` is the
  reference implementation — reuse that behaviour rather than reinventing it.

```erb
<%= tabler_ui.modal title: "Confirm",
                    dialog_html: { class: "modal-lg" },
                    body_html:   { data: { controller: "foo" } } %>
```

- When adding a new component, decide its parts up front and give each one a hook.
  A part with no hook is an incomplete component.

## JavaScript goes through Stimulus

Components render from Rails code. Any JavaScript behaviour is a Stimulus controller.
No `<script>` tags in templates, no inline `on*=` handlers, no `javascript:` URLs.

- Bootstrap's own JS keeps doing the work, but it is driven through a thin Stimulus
  controller rather than raw `data-bs-*` markup alone. The controller's job is
  lifecycle: instantiate the Bootstrap object in `connect()`, dispose it in
  `disconnect()`.
- Controller code stays clean and well structured:
  - `static values` are typed and carry defaults — `static values = { color: { type:
    String, default: "primary" } }`, never ad-hoc `this.element.dataset.foo` reads.
  - Targets are declared with `static targets` and guarded with `hasXTarget` before use.
  - Every `addEventListener`, timer, and third-party instance created in `connect()` is
    torn down in `disconnect()`. This matters because Turbo connects and disconnects
    controllers repeatedly.
  - Stay inside the controller's own scope. `document.querySelector` is a smell;
    page-wide writes (like theme on `documentElement`) need a comment saying why.
  - Shared logic goes in a helper module rather than being copy-pasted between
    controllers.
- Stimulus identifiers are namespaced `tabler-ui--<feature>`.
- Adding a controller means touching four places: the controller file, the import +
  `app.register` block in `app/assets/javascripts/tabler_ui.js`, the pin in
  `config/importmap.rb`, and the precompile list in `lib/tabler_ui/engine.rb`.

## A component is not finished until it has specs

- When a component is completed, its spec is written before the next component is
  started. Not batched up, not deferred.
- Applies to UI components and `FormBuilder` input methods. Stimulus controllers are
  exempt — they get a manual smoke check instead, since there is no JS test toolchain
  here.
- Each component spec covers: renders with only its mandatory arguments; the HTML hooks
  on every subcomponent contract via the shared example in
  `spec/support/shared_examples/html_hook.rb`; its option names resolving correctly;
  and a regression case for any bug the component was fixed for.
- `bundle exec rspec` must be green before moving on.

## Authorization: the auth: option

- Every component and subcomponent accepts an `auth:` option.
- Configure the check once, globally: `tabler_ui.set_auth_method { |value| ... }`.
  Defaults to always-true, so nothing changes for a host that never calls it.
- The configured method is invoked on every `tabler_ui.*` call, whether or not `auth:`
  was passed explicitly (an omitted `auth:` is just `nil` as the argument) — a falsy
  return means the component (or, for a subcomponent added in a later wave, that
  specific subcomponent) is not rendered at all, and its block never runs.
- A subcomponent that doesn't set its own `auth:` inherits its parent component's
  `auth:` value as the default (not `nil`) — this is being built out per-subcomponent
  in a later wave, so as of this commit only top-level components are gated.
- Unrelated to Navbar's own pre-existing `action:`/`subject:` + `can?` check — a
  separate, older, Navbar-only mechanism; both apply independently.

---

# Architecture brief

`tabler_ui` is a **Rails engine gem** (no host app in this repo) wrapping the Tabler
design system — Bootstrap 5, Tabler v1.4.0. Ruby >= 3.1, Rails >= 7. Specs run under RSpec + Combustion; `bundle exec rspec` boots a minimal dummy app
from `spec/internal/` and renders components through the real dispatcher.

## Layout

```
lib/tabler_ui/
  engine.rb        Rails::Engine — asset paths, precompile list, view paths, helper injection
  helper.rb        tabler_ui / tabler_form_with / tabler_ui_form_for — the public entry points
  ui.rb            component dispatcher (method_missing) + SlotContext
  form_builder.rb  ActionView::Helpers::FormBuilder subclass, Simple-Form style
app/components/tabler_ui/
  <name>/component.rb + _component.html.erb    class-backed components
  _<name>.html.erb                             bare-partial components
app/javascript/controllers/tabler_ui/          10 Stimulus controllers
app/assets/                                    Tabler CSS/JS, ApexCharts, ~5700 icons, ~200 illustrations
config/importmap.rb                            pins shipped to the host app
```

## The dispatcher — `lib/tabler_ui/ui.rb`

`tabler_ui.foo(**kwargs, &block)` resolves in this order:

1. Looks for `TablerUi::Foo::Component`. If found, inspects its `initialize`:
   - takes keyword args -> **modern**: `Component.new(**kwargs)`, renders `tabler_ui/foo/_component`
   - takes a positional arg -> **legacy**: `Component.new(view_context)`, then attributes
     are injected one by one via `public_send("#{k}=", v)`
2. No class -> wraps kwargs in an `OpenStruct` and renders the bare partial `tabler_ui/_foo`.

With a block, the dispatcher picks one of two paths by duck-typing the component: if it
responds to `add`, `left`, `right`, `buttons`, `actions`, `item` or `tab`, the block gets
**the component itself** (builder style). Otherwise it gets a **`SlotContext`**, exposed
to the partial as the `slots` local.

Adding a builder method named like one of those triggers the builder path — that list is
the switch.

## Component conventions

- `module TablerUi; module Name; class Component`, file at `app/components/tabler_ui/name/component.rb`.
- Constructors follow the Rails-conventional signatures rule: mandatory arguments
  positional, everything else in a trailing `options = {}` hash. See that rule for how
  the dispatcher resolves the caller's keyword syntax onto these positional parameters.
- Every component now uses the modern shape (`include TablerUi::Base` + the
  Rails-conventional signatures constructor). The legacy positional
  `initialize(view_context)` is gone; the dispatcher raises on a component class that
  does not include `TablerUi::Base`.
- The partial receives the component under its snake_case name (`alert`, `badge`, `navbar`).
- Computed CSS classes belong on the component as a method (`alert.alert_classes`), not in the ERB.
- `Icon`, `Illustration` and `DarkModeToggle` accept a `class:` kwarg, which collides with
  `Object#class`, and work around it with `binding.local_variable_get(:class)`. Under
  the Rails-conventional signatures rule that hack is obsolete — `options[:class]` just
  works. Do not add new uses of it.
- `# frozen_string_literal: true` at the top. Missing only in `icon` and `datagrid`.
- Builder-style components: `Navbar` (`left`/`right` -> `add`, `dropdown`, `divider`),
  `Dropdown` (`item`/`divider`/`header`), `Tabs` (`tab`), `SettingsPage` (`item`),
  `Datagrid` (`item`). Blocks are stored as Procs and rendered with `capture(&item.content)`.
- `Icon` and `Illustration` read raw SVG off disk — gem dir first, then the host app's
  `app/assets/{icons,illustrations}/` — and are emitted with `raw`. That is the override hook.

## Bare partials

Rendered with an `OpenStruct`, so:
- Use bracket access for names that collide with Ruby methods: `button[:class]`, `button[:method]`.
- Guard slots with `defined?(slots)` before touching them.
- No defaults come from anywhere else — the partial supplies them or renders nothing.

Current bare partials: `_button`, `_card` (slots: header/body/footer), `_page_header`
(slot: buttons), `_table`, `_stat_card`, `_progress`, `_avatar`.

## JavaScript

- Stimulus IDs are namespaced `tabler-ui--<feature>`, e.g. `data-controller="tabler-ui--datepicker"`.
- `app/assets/javascripts/tabler_ui.js` self-registers controllers against `window.Stimulus`
  (set by the host app). Adding a controller means touching **four** places: the file,
  the import + `app.register` block in `tabler_ui.js`, the pin in `config/importmap.rb`,
  and the precompile list in `engine.rb`.
- Bootstrap's own JS (bundled inside `tabler_ui/tabler.js`, exposed as `window.tabler.bootstrap`)
  keeps doing the interactive work for tabs/lists, collapse and dropdowns; `tab_controller`,
  `collapse_controller`, `dropdown_menu_controller` and `alert_controller` are thin lifecycle
  wrappers (instantiate in `connect()`, dispose in `disconnect()`) driven by the `data-bs-*`
  attributes already in the markup.
- External deps: `vanillajs-datepicker` (CDN pin), `star-rating.js` and `apexcharts` (bundled).

## Gotchas

- `FormBuilder#input` derives a method name from the DB column type and `send`s it.
  `:date`, `:integer`, `:decimal`, `:float`, `:datetime` and `:time` all route through
  `string_input`/`string_field`'s own finer-grained dispatch (see `lib/tabler_ui/form_builder.rb`).
  An unrecognized type with no explicit `as:` raises `ArgumentError` (not `NoMethodError`),
  naming the field/type and suggesting `as:` or a new `#<type>_input` method.
- User-facing strings in `form_builder.rb` and `illustration/component.rb` are hardcoded
  German. New strings should not add to that.
- `README.md` documents ~7 of the 19 components and is out of date.
- `USAGE.md` is the generated, exhaustive alternative -- regenerate it with `rake tabler_ui:usage_doc` after touching a component's doc comments or a demos file.
