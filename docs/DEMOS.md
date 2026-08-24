# The demo system

One ERB string is both rendered live and printed as the code sample underneath
it. That is the entire point of this mechanism: the old showcase kept live
ERB in a view and its "matching" code sample in a separate 108-entry
`SNIPPETS` hash (`showcase/app/helpers/showcase_helper.rb`), and the two
drifted — readers saw code that did not produce the example above it (see
`content_21`, `layout_28` in that file's history for concrete cases; two more
turned up while building this: see "Drift found while porting" below).
Here there is exactly one string per demo. It cannot drift from itself.

This file is the contract. Three other agents write demo content against it
in parallel and are expected to read only this file plus the five reference
files under `docs/lib/tabler_ui/docs/demos/` (`badge_demos.rb`,
`alert_demos.rb`, `avatar_demos.rb`, `spinner_demos.rb`, `progress_demos.rb`)
— nothing else in this codebase should need reading to write a new
`*_demos.rb` file.

## The DSL

```ruby
# docs/lib/tabler_ui/docs/demos/badge_demos.rb
# frozen_string_literal: true

TablerUi::Docs::DemoRegistry.define(:badge) do |c|
  c.demo :colors,
         title: "colors, light, pill, outline, icon, notification",
         source: <<~'ERB'
           <%= tabler_ui.badge text: "New", color: "blue" %>
           <%= tabler_ui.badge text: "Pending", color: "yellow", light: true %>
         ERB

  c.demo :dot,
         title: "dot: true (fixed 10px dot; raises if combined with text/icon/content)",
         source: <<~'ERB'
           <%= tabler_ui.badge color: "red", dot: true %>
         ERB
end
```

- One file per component: `docs/lib/tabler_ui/docs/demos/<component>_demos.rb`.
  `<component>` is the exact symbol you'd pass to `TablerUi::Docs::DemoRegistry.for` —
  in practice, the same name used as `tabler_ui.<component>` in the demo's own
  ERB. `badge` and `badge_list` are two different components (two different
  `TablerUi::*::Component` classes) and therefore two different files —
  don't fold a related-but-separate component's demos into another
  component's file just because the old showcase happened to show them on
  the same page.
- `DemoRegistry.define(component_sym) { |c| ... }` opens the file's one
  block. `component_sym` is applied to every `c.demo` call inside it — you
  never repeat the component name per demo.
- `c.demo(id, title:, source:, locals: nil)`:
  - `id` — a `Symbol`, unique **within this component**. Reusing an id in
    the same component raises `DemoRegistry::DuplicateDemoError` at load
    time (i.e. gem boot, not "the first time someone visits the page" — see
    "Where demo files get loaded" below).
  - `title` — a human string describing what the demo shows. Do **not**
    prefix it with the component name — `"colors, light, pill"`, not
    `"badge - colors, light, pill"`. The component is already implied by
    the file/`define` call; the old showcase's titles had that prefix
    because one page showed every component together and needed it to
    disambiguate. Strip it when porting (see "Porting a demo" below).
  - `source` — the ERB, both rendered and printed. Always a **single-quoted
    heredoc**, `<<~'ERB'`. See "Why `.rb`, not `.erb`" below for why this
    is not optional.
  - `locals:` — optional. See "Stateful demos" below.

## The `Demo` object

Every `c.demo` call builds one `TablerUi::Docs::Demo`
(`docs/lib/tabler_ui/docs/demo.rb`), exposing:

| method       | what it is                                                          |
|--------------|----------------------------------------------------------------------|
| `id`         | the `Symbol` passed to `c.demo`                                      |
| `component`  | the `Symbol` passed to `DemoRegistry.define`                         |
| `title`      | the `title:` string, verbatim                                        |
| `toc_label`  | `title`, shortened for the Contents column nav (`TablerUi::Docs::TocLabel.shorten`) when it's long — unchanged when it's already short. `title` itself (used for the demo card heading) is never touched. |
| `source`     | the `source:` ERB string, verbatim                                   |
| `locals`     | the `locals:` Proc, or `nil`                                         |
| `slug`       | `"<component>-<id>"`, e.g. `"badge-colors"` — globally unique (see below), used for anchors, search, and `DemoRegistry.find` |
| `resolved_locals` | `locals ? locals.call : {}` — see "Stateful demos"               |

## `DemoRegistry`

`docs/lib/tabler_ui/docs/demo_registry.rb`. Public API, all class methods:

- `DemoRegistry.define(component) { |c| ... }` — see DSL above.
- `DemoRegistry.all` → `Array<Demo>`, every demo, every component.
- `DemoRegistry.for(component)` → `Array<Demo>` for one component, in
  registration order. Unknown component → `[]`, never raises.
- `DemoRegistry.find(slug)` → the `Demo` with that slug, or `nil`.
- `DemoRegistry.components` → `Array<Symbol>`, every component with at
  least one demo.
- `DemoRegistry.load_demos!` — requires every `docs/lib/tabler_ui/docs/demos/*_demos.rb`
  file. You will not normally call this yourself; see below.

**Uniqueness is enforced at registration time, twice**: an id colliding
within one component raises immediately, and — separately — every demo's
full `slug` is checked against every other demo's slug ever registered,
across all components. The second check exists because `slug` is a plain
string concatenation (`"#{component}-#{id}"`); if a component or id symbol
ever contained a literal `-`, two different `(component, id)` pairs could
concatenate to the identical string even though neither one, on its own,
reused anything. In practice component/id symbols are always plain
snake_case, so this never fires — but it's a one-line guard against a typo
that would otherwise silently merge two demos' anchors. See
`spec/lib/tabler_ui/docs/demo_registry_spec.rb` ("raises when two different
(component, id) pairs concatenate to the same slug") for the constructed
case that proves it.

## Where demo files get loaded

`docs/lib/tabler_ui/docs.rb` — the file `require "tabler_ui/docs"` resolves
to (see `lib/tabler_ui.rb`, which does `require "tabler_ui/docs" if
defined?(Rails)`) — calls `TablerUi::Docs::DemoRegistry.load_demos!`
unconditionally, right after requiring `Demo` and `DemoRegistry`. This means
every demo is registered **eagerly, at gem boot**, not lazily the first time
some controller renders a component's page. Eager was chosen over lazy
specifically so that a mistake (a duplicate id, an id/component pair that
collides with another demo's slug) fails the whole app boot — and so fails
CI / `bundle exec rspec` immediately — rather than only failing whenever
somebody first visits that one page, potentially long after the bad commit
landed.

**Loading twice is safe and cheap, by construction, not by any dedup logic
in this codebase.** `load_demos!` calls plain `require` (never `load`) on
each file's absolute path. Ruby's own `$LOADED_FEATURES` tracking is what
makes a second `require` of the same absolute path a no-op — the file's top
level `TablerUi::Docs::DemoRegistry.define(...)` call simply does not run
again, so nothing re-registers. `spec/lib/tabler_ui/docs/demo_registry_spec.rb`
("is idempotent") calls `load_demos!` twice back to back and asserts every
component's demo count is unchanged, proving this rather than assuming it.

If you add a new `docs/lib/tabler_ui/docs/demos/<component>_demos.rb` file,
you do not need to register it anywhere else — `load_demos!` globs
`demos/*.rb` next to itself and requires whatever it finds, so a new file
is picked up automatically the next time the gem boots (i.e. the next
`bundle exec rspec` run, or dev server restart).

## Why `.rb`, not `.erb`

**Demo definitions must live in a plain `.rb` file. Never a `.erb` file.**

ERB's own tag scanner is a naive text scan for `<%`/`%>` with no awareness
of Ruby's heredoc or string nesting. If a demo's ERB source were written as
a heredoc *embedded inside another `.erb` file's own `<% %>` tag*, the
outer file's ERB compiler would see the heredoc's own `<%`/`%>` characters
as its own tags and mis-parse the whole template — this was confirmed
empirically while building the original showcase (see the header comment of
`showcase/app/helpers/showcase_helper.rb`, which hit exactly this and
avoided it the same way: a plain `.rb` file, not `.erb`).

In a `.rb` file, `<%` and `%>` inside a heredoc are just ordinary
characters — nothing is scanning for them. That is the entire reason demo
files are `.rb`.

**Use a single-quoted heredoc**, `<<~'ERB'` (note the quotes around `ERB`),
not `<<~ERB`. A double-quoted (or bare) heredoc is still interpolated *by
Ruby itself* before the string ever reaches ERB — `#{...}` inside the demo's
ERB source (unlikely, but also `"#{...}"` accidentally typed where `<%= ... %>`
was meant) would be evaluated at Ruby-parse time in the demo file's own
binding, not rendered as part of the template. Single-quoting the heredoc
delimiter turns off Ruby interpolation entirely, so the ERB tags reach
`render inline:` untouched.

`render inline:` itself is safe regardless — it compiles the string
directly through ActionView's template compiler rather than scanning for
tags the way parsing a `.erb` *file* does. The trap is specifically about
*storing* the source inside a `.erb` file; rendering it via `render inline:`
was never the risk.

## Rendering: how one `Demo` becomes a page

`docs/app/views/tabler_ui/docs/demos/_demo.html.erb` takes a `demo:` local
(one `Demo`) and renders both consumers from the same `demo.source`:

```erb
<%= tabler_ui.card title: demo.title, html: { class: "mb-4", id: demo.slug } do |s| %>
  <% s.body do %>
    <div class="docs-demo-example">
      <%= render inline: demo.source, locals: demo.resolved_locals %>
    </div>
    <pre class="bg-dark-lt rounded p-2 mb-0"><code><%= demo.source.strip %></code></pre>
  <% end %>
<% end %>
```

- **Live**: `render inline: demo.source, locals: demo.resolved_locals`.
- **Source**: `demo.source.strip`, printed through `<%= %>` — a plain Ruby
  `String`, so ERB auto-escapes it (`<` becomes `&lt;`, etc.) exactly the
  way the old showcase's `_example.html.erb` did with its `code.strip`.
  Nothing manually escapes it; auto-escaping is what makes the `<pre><code>`
  block show `<%= tabler_ui.badge ... %>` as text instead of trying to
  execute it.
- **Framing**: wrapped in `tabler_ui.card title: demo.title`, mirroring the
  shape of `showcase/app/views/showcase/_example.html.erb` (`tabler_ui.card`
  with a `body` slot holding the example then the `<pre>`). `demo.slug` is
  set as the card's `id:` so a URL can deep-link to `#badge-colors`.

Render it for a whole component's demos with:

```erb
<% TablerUi::Docs::DemoRegistry.for(:badge).each do |demo| %>
  <%= render "tabler_ui/docs/demos/demo", demo: demo %>
<% end %>
```

`docs/app/controllers/tabler_ui/docs/demos_controller.rb` +
`docs/app/views/tabler_ui/docs/demos/show.html.erb` do exactly this, wired
up at `GET /ui/demos/:component` (`docs/config/routes.rb`) — visit
`/ui/demos/badge` against the mounted engine to see the mechanism live.
That controller/route exists only to prove the mechanism is reachable
end-to-end; the real per-component doc page (navigation, breadcrumbs, the
parsed `@example` YARD blocks alongside these runnable demos) is other
agents' work.

### `render inline:` and the template cache — verified, not assumed

Checked against the installed `actionview` gem
(`actionview-8.1.3.1/lib/action_view/renderer/template_renderer.rb` and
`.../lib/action_view/template.rb`):

- `TemplateRenderer#determine_template` builds a **brand-new**
  `Template::Inline.new(options[:inline], ...)` object on every single call
  to `render inline: ...`. There is no cache keyed by source string, or by
  anything else — two calls with byte-identical `inline:` strings still get
  two distinct `Template::Inline` instances.
- `Template#method_name` (the name of the method the template compiles to)
  is `"_#{identifier_method_name}__#{@identifier.hash}_#{__id__}"` —
  critically, it includes `__id__`, the new `Template::Inline` instance's
  own Ruby object id. Since step 1 guarantees a fresh instance per call,
  `__id__` is different every time, so the compiled method name is
  different every time, regardless of whether `@identifier.hash` (derived
  from the literal string `"inline template"`, not the source — every
  inline template shares that identifier) would collide.
- `Template::Inline#compile` registers an `ObjectSpace` finalizer that
  removes the compiled method from the module once the `Template::Inline`
  object itself is garbage collected, so these don't accumulate forever
  either.

**Conclusion: two demos rendered on the same page can never collide in the
template cache, and neither can the same demo rendered twice (e.g. once in
a spec, once on a live page).** Each `render inline:` call gets its own
compiled method, full stop — there was no cache to have a bug in.

## Stateful demos: `locals:`

Most demos are pure — literal strings and numbers, no lookup needed. For
one that needs a value built at render time (a fresh in-memory struct
standing in for a record, a computed range, anything that shouldn't be
inlined as a literal in the ERB itself), pass `locals:` as a zero-argument
`Proc` returning a `Hash`:

```ruby
c.demo :with_rows,
       title: "table - striped, hover, computed row class",
       locals: -> { { rows: [{ name: "Ada", status: "Active" }, { name: "Chip", status: "Away" }] } },
       source: <<~'ERB'
         <%= tabler_ui.table columns: [...], data: rows, striped: true %>
       ERB
```

`Demo#resolved_locals` calls the proc — `locals ? locals.call : {}` — and
the result is passed straight through as `render inline:`'s `locals:`
option, so `rows` becomes an ordinary local variable inside `source`. The
proc is called **lazily, at render time**, never at registration time in
`c.demo` itself — so if it builds a fresh object (rather than closing over
a constant), every render gets its own fresh value, and nothing is
constructed for a demo that's never rendered on the current page.

None of the five reference demo files need this — badge, alert, avatar,
spinner and progress are all fully expressible as literals in the ERB
itself. Reach for `locals:` only when a literal in the source itself would
be unreadable or the demo genuinely needs a computed/non-literal value.

## Porting a demo from the old showcase

The old showcase (`showcase/app/views/showcase/*.html.erb` +
`showcase/app/helpers/showcase_helper.rb`'s `SNIPPETS` hash) is being
retired in favor of this mechanism. To port one of its examples:

1. Find the `render layout: "showcase/example", locals: { title: "...",
   code: snippet(:some_key) }` block in the relevant `showcase/app/views/showcase/*.html.erb`
   file. The block's body — between `do %>` and `<% end %>` — is the **live**
   ERB that was actually rendered.
2. **Use that live block as the source of truth, not the `SNIPPETS[:some_key]`
   entry.** They were maintained separately and are not guaranteed to
   match — that drift is the whole reason this mechanism exists. While
   porting the five reference components, two real cases of drift turned up
   (see below); always diff the two before trusting the snippet.
3. Strip the `"<component> - "` prefix off the old title for `title:`
   (the component is now implied by the file/`define` call).
4. Pick an `id:` — a short symbol capturing what's distinct about this demo
   relative to the component's other demos (`:colors`, `:dot`, `:cover`,
   `:overlay`, ...), not a numbered `content_NN`-style id.
5. Paste the live block's body, verbatim, into a `<<~'ERB'` heredoc as
   `source:`.
6. Add the demo to (or create) `docs/lib/tabler_ui/docs/demos/<component>_demos.rb`.
   Run `bundle exec rspec spec/lib/tabler_ui/docs/demo_registry_spec.rb` —
   the "every registered demo renders via `render inline:` without raising"
   example covers your new demo automatically, no extra spec needed on your
   end for that guarantee.

### Drift found while porting the five reference components

- `avatar` (`content_30` / `cover: true`): the `SNIPPETS` entry showed only
  the bare `tabler_ui.avatar ..., cover: true` call. The live block wrapped
  it in a banner `<div>` — `cover:` pulls the avatar up over a *preceding*
  element via negative margin, so without that element the effect is
  invisible. The snippet's reader saw code that could not have produced the
  screenshot above it. Ported from the live block, banner div included —
  see the `:cover` demo in `docs/lib/tabler_ui/docs/demos/avatar_demos.rb`.
- `avatar` (`content_31` / overlay slot): the `SNIPPETS` entry showed one
  `md`-sized avatar. The live block showed two — `md` and `xl`, each in a
  spacing `<span>` — specifically to compare how the overlay slot scales
  across sizes; the snippet silently dropped the `xl` half of the
  comparison. Ported from the live block, both sizes included — see the
  `:overlay` demo in the same file.
- `spinner` (`content_14`): the `SNIPPETS` entry showed four bare
  `tabler_ui.spinner` calls with no wrapping markup. The live block wrapped
  each in `<span class="me-3">`, which is what actually produced the
  visible gaps between them. Cosmetic rather than misleading about
  behaviour, but still not what was printed — ported from the live block.
  See `docs/lib/tabler_ui/docs/demos/spinner_demos.rb`.

`badge`, `alert` and `progress` had no drift for the demos ported here —
`SNIPPETS` matched the live block in every case — but were still ported
from the live block rather than the snippet, on the same principle: this
file is what a reader now checks the rendered example against, not the old
showcase, so it should not depend on the old snippet having been correct.

## Reference implementation

`docs/lib/tabler_ui/docs/demos/badge_demos.rb`,
`docs/lib/tabler_ui/docs/demos/alert_demos.rb`,
`docs/lib/tabler_ui/docs/demos/avatar_demos.rb`,
`docs/lib/tabler_ui/docs/demos/spinner_demos.rb` and
`docs/lib/tabler_ui/docs/demos/progress_demos.rb` are the five components
built against this contract. Each file's own header comment names exactly
which `showcase/app/views/showcase/*.html.erb` block and `SNIPPETS` key it
was ported from, and whether drift was found. Copy their shape for a new
component's file.
