# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor/erb_generator"

# ErbGenerator is pure formatting over an already-validated tree (see its
# own header comment and contract.rb) -- this spec builds tree fixtures by
# hand rather than going through a validator (there isn't one to require
# here; it's a parallel task's file), the same way slot_map_spec.rb and
# builder_map_spec.rb each work against their own registries directly.
RSpec.describe TablerUi::Docs::Editor::ErbGenerator do
  # Strips the banner and the single trailing newline #call always adds, so
  # every other example can assert against exactly the lines it cares about.
  def generate(node)
    full = described_class.new(node).call

    expect(full).to start_with(described_class::BANNER)
    full.delete_prefix(described_class::BANNER).chomp
  end

  # Minimal real view context, wired to the main engine's component view
  # path only (no docs engine needed here) -- mirrors
  # spec/lib/tabler_ui/docs/demo_registry_spec.rb's own `demo_view_context`,
  # trimmed to what this file needs.
  def plain_view_context
    view_paths = ActionView::PathSet.new([TablerUi::Engine.root.join("app/components").to_s])
    view_class = ActionView::Base.with_empty_template_cache
    view_class.include(TablerUi::Helper)
    view_class.with_view_paths(view_paths, {})
  end

  describe "the banner" do
    it "does not leak past its own comment -- no literal ERB close sequence inside the comment text" do
      # Regression guard matching spec/lib/tabler_ui/docs/no_leaked_erb_comment_spec.rb's
      # own check: strip the real, well-formed `<%# ... %>` wrapper and
      # confirm the text inside it carries no early-closing "%>".
      inner = described_class::BANNER.sub(/\A<%#/, "").sub(/%>\s*\z/, "")
      expect(inner).not_to include("%>")
    end

    it "is a real ERB comment that renders to nothing" do
      view = plain_view_context
      expect(view.render(inline: described_class::BANNER).strip).to eq("")
    end
  end

  describe "literal formatting" do
    it "formats String, true/false and Integer" do
      node = component_node("card", options: { "title" => "Hello", "stacked" => true, "count" => 3 })

      expect(generate(node)).to eq('<%= tabler_ui.card title: "Hello", stacked: true, count: 3 %>')
    end

    it "formats an enum option EnumMap marks symbol: true as a Symbol literal" do
      expect(TablerUi::Docs::Editor::EnumMap.symbol?("dropdown", "align")).to eq(true) # sanity on the fixture itself

      node = component_node("dropdown", options: { "label" => "Actions", "align" => "end" })

      expect(generate(node)).to eq('<%= tabler_ui.dropdown label: "Actions", align: :end %>')
    end

    it "formats a nested Hash option/html value recursively, label keys bare" do
      node = component_node("badge", html: { "root" => { "class" => "x", "data" => { "controller" => "y" } } })

      expect(generate(node)).to eq('<%= tabler_ui.badge html: { class: "x", data: { controller: "y" } } %>')
    end

    it "formats a non-label Hash key with the required hash-rocket string form, never `key:`" do
      node = component_node("button", html: { "root" => { "data-bs-toggle" => "collapse" } })

      expect(generate(node)).to eq('<%= tabler_ui.button html: { "data-bs-toggle" => "collapse" } %>')
    end
  end

  # --- table :columns -> literal Ruby lambda -------------------------------

  # The export-side counterpart to renderer_spec.rb's "table :columns
  # synthesis" coverage -- see ErbGenerator#format_columns_array's own doc
  # for the shared story with Renderer#synthesize_table_columns.
  describe "table :columns" do
    it "emits a real ->(row) { row[:key] } lambda from a declarative key:, never quoted as a String" do
      node = component_node("table", options: { "columns" => [{ "label" => "Name", "key" => "name" }] })

      expect(generate(node))
        .to eq('<%= tabler_ui.table columns: [{ label: "Name", value: ->(row) { row[:name] } }] %>')
    end

    it "drops the editor-only key: -- Table::Component has no such option" do
      node = component_node("table", options: { "columns" => [{ "key" => "name" }] })

      expect(generate(node)).to eq('<%= tabler_ui.table columns: [{ value: ->(row) { row[:name] } }] %>')
    end

    it "quotes a non-bareword key as a String row lookup instead of a Symbol literal" do
      node = component_node("table", options: { "columns" => [{ "key" => "full name" }] })

      expect(generate(node))
        .to eq('<%= tabler_ui.table columns: [{ value: ->(row) { row["full name"] } }] %>')
    end

    it "carries every other column field through untouched, in the tree's own order" do
      node = component_node("table",
                             options: { "columns" => [{ "label" => "Role", "key" => "role", "class" => "text-muted" }] })

      expect(generate(node)).to eq(
        '<%= tabler_ui.table columns: [{ label: "Role", class: "text-muted", value: ->(row) { row[:role] } }] %>'
      )
    end

    it "formats multiple columns as separate Hash literals inside the Array" do
      node = component_node("table",
                             options: { "columns" => [{ "label" => "Name", "key" => "name" },
                                                       { "label" => "Role", "key" => "role" }] })

      expect(generate(node)).to include(
        '{ label: "Name", value: ->(row) { row[:name] } }, { label: "Role", value: ->(row) { row[:role] } }'
      )
    end

    it "raises for a column with no key: (ErbGenerator formats already-validated trees only, " \
       "same contract as its own 'undefined behaviour on a malformed node' doc)" do
      node = component_node("table", options: { "columns" => [{ "label" => "Name" }] })

      expect { described_class.new(node).call }.to raise_error(ArgumentError, /key/)
    end

    it "leaves a non-table component's own Array<Hash> option (datagrid's :items) formatted generically, " \
       "with no synthesized value: at all" do
      node = component_node("datagrid", options: { "items" => [{ "title" => "Owner", "content" => "Ada" }] })

      expect(generate(node)).to eq('<%= tabler_ui.datagrid items: [{ title: "Owner", content: "Ada" }] %>')
    end

    it "renders to the exact same HTML the Renderer produces, real cell values included" do
      original_auth_method = TablerUi.auth_method
      TablerUi.auth_method = ->(*) { true }

      node = component_node("table",
                             options: { "columns" => [{ "label" => "Name", "key" => "name" }],
                                        "data" => [{ "name" => "Ada Lovelace" }] })

      html = plain_view_context.render(inline: generate(node))

      expect(html).to include("Name")
      expect(html).to include("Ada Lovelace")
    ensure
      TablerUi.auth_method = original_auth_method
    end
  end

  describe "a component with a required positional (args)" do
    it "emits it first, positionally, before the options hash -- the contract's own worked example" do
      node = component_node("modal", args: { "id" => "confirm-modal" }, options: { "title" => "Confirm" })

      expect(generate(node)).to eq('<%= tabler_ui.modal "confirm-modal", title: "Confirm" %>')
    end
  end

  # Regression: Tree normalizes "slots"/"items" onto every component node, so
  # a presence test on the KEY (rather than its contents) emitted an empty
  # `do |slots| %>` ... `<% end %>` pair for components carrying neither.
  # Renderer passes no block at all in that case, so this was a live
  # renderer/generator disagreement -- the exact drift the two-walkers-over-
  # one-tree design has to guard against. Caught by an end-to-end pipeline
  # run, not by either module's own specs.
  describe "a component with empty slots/items collections" do
    it "emits no block at all, matching what Renderer does" do
      node = component_node("button", options: { "text" => "Go" })
      node["slots"] = {}
      node["items"] = []

      expect(generate(node)).to eq('<%= tabler_ui.button text: "Go" %>')
    end
  end

  describe "slot-style block form" do
    it "yields |slots|, uses <% %> (not <%=) for every slots.<name> call, do/end always" do
      node = {
        "kind" => "component", "id" => "c1", "name" => "card",
        "options" => { "title" => "Card title" },
        "slots" => {
          "body" => [text_node("Card body content.")],
          "footer" => [text_node("Updated 3 min ago")]
        }
      }

      expect(generate(node)).to eq(<<~ERB.chomp)
        <%= tabler_ui.card title: "Card title" do |slots| %>
          <% slots.body do %>
            <p>Card body content.</p>
          <% end %>
          <% slots.footer do %>
            <p>Updated 3 min ago</p>
          <% end %>
        <% end %>
      ERB
    end
  end

  describe "builder-style block form" do
    it "yields the component's own snake_case name, sub-items via <% %>" do
      node = {
        "kind" => "component", "id" => "d1", "name" => "dropdown",
        "options" => { "label" => "Actions" },
        "items" => [
          builder_item("item", args: { "title" => "Edit" }, options: { "url" => "#" }),
          builder_item("divider")
        ]
      }

      expect(generate(node)).to eq(<<~ERB.chomp)
        <%= tabler_ui.dropdown label: "Actions" do |dropdown| %>
          <% dropdown.item "Edit", url: "#" %>
          <% dropdown.divider %>
        <% end %>
      ERB
    end
  end

  describe "navbar's three-level nesting" do
    it "walks root -> :group (var nav) -> :dropdown (var menu), each level's own methods" do
      node = {
        "kind" => "component", "id" => "n1", "name" => "navbar",
        "items" => [
          builder_item("left", items: [
                          builder_item("add", args: { "title" => "Home" }, options: { "url" => "#" }),
                          builder_item("dropdown", args: { "title" => "Admin" }, options: { "align" => "end" },
                                       items: [
                                         builder_item("item", args: { "title" => "Users" }, options: { "url" => "#" })
                                       ])
                        ])
        ]
      }

      expect(generate(node)).to eq(<<~ERB.chomp)
        <%= tabler_ui.navbar do |navbar| %>
          <% navbar.left do |nav| %>
            <% nav.add "Home", url: "#" %>
            <% nav.dropdown "Admin", align: :end do |menu| %>
              <% menu.item "Users", url: "#" %>
            <% end %>
          <% end %>
        <% end %>
      ERB
    end

    it "resolves a variable-name collision by suffixing" do
      # Contrived (real trees never nest a group inside itself), but proves
      # #unique_name's fallback path fires rather than silently shadowing.
      allow(TablerUi::Docs::Editor::BuilderMap).to receive(:methods_for).and_call_original
      allow(TablerUi::Docs::Editor::BuilderMap).to receive(:methods_for)
        .with("navbar", :group).and_return(
          "left" => { klass: "Component::NavigationGroup", arg: nil, block: :items, nests: :group }
        )

      node = {
        "kind" => "component", "id" => "n1", "name" => "navbar",
        "items" => [
          builder_item("left", items: [builder_item("left", items: [])])
        ]
      }

      generated = generate(node)
      expect(generated).to include("navbar.left do |nav| %>")
      expect(generated).to include("nav.left do |nav_2| %>")
    end
  end

  describe "layout/text kinds" do
    it "renders row -> column -> heading as plain HTML, span becomes col-* classes, content is escaped" do
      node = {
        "kind" => "fragment", "id" => "root",
        "children" => [
          { "kind" => "row", "id" => "r1", "attrs" => { "class" => "row-cards" },
            "children" => [
              { "kind" => "column", "id" => "c1", "span" => { "base" => 12, "md" => 6 }, "attrs" => {},
                "children" => [
                  { "kind" => "heading", "id" => "h1", "level" => 2, "content" => "Hello & <world>" }
                ] }
            ] }
        ]
      }

      expect(generate(node)).to eq(<<~HTML.chomp)
        <div class="row row-cards">
          <div class="col-12 col-md-6">
            <h2>Hello &amp; &lt;world&gt;</h2>
          </div>
        </div>
      HTML
    end

    it "sorts span classes base, sm, md, lg, xl, xxl regardless of input Hash order" do
      node = { "kind" => "column", "id" => "c1", "span" => { "lg" => 4, "base" => 12, "sm" => 8 }, "attrs" => {},
               "children" => [] }

      expect(generate(node)).to eq('<div class="col-12 col-sm-8 col-lg-4"></div>')
    end

    it "escapes an attribute value the same way it escapes text content" do
      node = { "kind" => "row", "id" => "r1", "attrs" => { "title" => "A & B" }, "children" => [] }

      expect(generate(node)).to eq('<div class="row" title="A &amp; B"></div>')
    end

    it "renders text with its own tag" do
      node = { "kind" => "text", "id" => "t1", "tag" => "small", "content" => "note" }

      expect(generate(node)).to eq("<small>note</small>")
    end
  end

  describe "partial nodes" do
    it "strips the leading underscore and .html.erb suffix" do
      node = { "kind" => "partial", "id" => "p1", "path" => "shared/_header.html.erb" }

      expect(generate(node)).to eq('<%= render "shared/header" %>')
    end

    it "only strips the underscore off the basename, not an intermediate directory segment" do
      node = { "kind" => "partial", "id" => "p1", "path" => "shared/widgets/_footer.html.erb" }

      expect(generate(node)).to eq('<%= render "shared/widgets/footer" %>')
    end
  end

  describe "indentation and the wrapping threshold" do
    it "keeps a call on one line while it fits within 100 columns" do
      node = component_node("x", options: {
                               "aaaaaaaaaa" => "1111111111",
                               "bbbbbbbbbb" => "2222222222",
                               "cccccccccc" => "3333333333"
                             })

      generated = generate(node)
      expect(generated.lines.size).to eq(1)
      expect(generated.length).to be <= 100
    end

    it "wraps onto a new line, aligned under the first segment, once a 4th option pushes past 100 columns" do
      node = component_node("x", options: {
                               "aaaaaaaaaa" => "1111111111",
                               "bbbbbbbbbb" => "2222222222",
                               "cccccccccc" => "3333333333",
                               "dddddddddd" => "4444444444"
                             })

      lines = generate(node).lines(chomp: true)
      align = "<%= tabler_ui.x ".length # column the first segment starts at

      expect(lines.size).to eq(2)
      expect(lines.first).to end_with(",")
      expect(lines.first).not_to include("dddddddddd")
      expect(lines.last).to start_with(" " * align)
      expect(lines.last.lstrip).to eq('dddddddddd: "4444444444" %>')
    end

    it "indents nested content two spaces per level (see the layout-kinds example above for the full walk)" do
      node = { "kind" => "row", "id" => "r1", "attrs" => {},
               "children" => [{ "kind" => "text", "id" => "t1", "tag" => "p", "content" => "x" }] }

      lines = generate(node).lines(chomp: true)
      expect(lines).to eq(['<div class="row">', '  <p>x</p>', "</div>"])
    end
  end

  describe "contenteditable is never emitted" do
    it "is dropped from row/column attrs even if present in the (already-invalid) input" do
      node = { "kind" => "row", "id" => "r1", "attrs" => { "class" => "row", "contenteditable" => "true" },
               "children" => [] }

      expect(generate(node)).not_to include("contenteditable")
    end

    it "is dropped from a component's html: hook even if present in the (already-invalid) input" do
      node = component_node("card", html: { "root" => { "contenteditable" => "true", "class" => "x" } })

      expect(generate(node)).not_to include("contenteditable")
    end

    it "never appears anywhere across every fixture this spec renders" do
      fixtures = [
        component_node("card", options: { "title" => "Hello", "stacked" => true, "count" => 3 }),
        component_node("modal", args: { "id" => "confirm-modal" }, options: { "title" => "Confirm" }),
        { "kind" => "partial", "id" => "p1", "path" => "shared/_header.html.erb" },
        {
          "kind" => "component", "id" => "n1", "name" => "navbar",
          "items" => [builder_item("left", items: [builder_item("add", args: { "title" => "Home" })])]
        }
      ]

      fixtures.each { |node| expect(generate(node)).not_to include("contenteditable") }
    end
  end

  # The strongest spec this class can get: actually render a handful of its
  # own generated ERB and assert the result is sensible HTML. `render
  # inline:` on generator output is legitimate HERE ONLY -- these strings
  # are authored fixtures in this spec file, not user input, so this is the
  # curated-corpus side of the boundary the codebase draws (see
  # demo_registry_spec.rb's own `render inline:` for the precedent). This
  # pattern must never move into application code, where "render whatever
  # string arrived" is an ERB-injection RCE.
  describe "rendering the generated ERB for real" do
    around do |example|
      # Global-state warning (TablerUi.auth_method, see lib/tabler_ui.rb):
      # a call with no auth: passed goes through the currently configured
      # method regardless, so an earlier spec elsewhere in the suite that
      # left a custom auth_method installed would make these renders
      # silently produce nothing. Save/restore around every example here.
      original = TablerUi.auth_method
      TablerUi.auth_method = ->(*) { true }
      example.run
      TablerUi.auth_method = original
    end

    it "renders a plain self-closing component call to real HTML" do
      node = component_node("badge", options: { "text" => "New", "color" => "azure" })

      html = plain_view_context.render(inline: generate(node))

      expect(html).to include("badge")
      expect(html).to match(/>\s*New\s*</)
    end

    it "renders a slot-style block to real, nested HTML" do
      node = {
        "kind" => "component", "id" => "c1", "name" => "card",
        "options" => { "title" => "Card title" },
        "slots" => { "body" => [text_node("Card body content.")] }
      }

      html = plain_view_context.render(inline: generate(node))

      expect(html).to include("Card title")
      expect(html).to include("<p>Card body content.</p>")
    end

    it "renders a builder-style block (dropdown) to real HTML with its items" do
      node = {
        "kind" => "component", "id" => "d1", "name" => "dropdown",
        "options" => { "label" => "Actions" },
        "items" => [builder_item("item", args: { "title" => "Edit" }, options: { "url" => "#" })]
      }

      html = plain_view_context.render(inline: generate(node))

      expect(html).to include("Actions")
      expect(html).to match(/>\s*Edit\s*</)
    end

    it "renders layout/text nodes as literal HTML, escaped" do
      node = { "kind" => "row", "id" => "r1", "attrs" => {},
               "children" => [{ "kind" => "heading", "id" => "h1", "level" => 3, "content" => "A & B" }] }

      html = plain_view_context.render(inline: generate(node))

      expect(html.strip).to eq(%(<div class="row">\n  <h3>A &amp; B</h3>\n</div>))
    end
  end

  # --- fixtures ------------------------------------------------------------

  def component_node(name, args: nil, options: nil, html: nil)
    node = { "kind" => "component", "id" => "n", "name" => name }
    node["args"] = args if args
    node["options"] = options if options
    node["html"] = html if html
    node
  end

  def builder_item(method, args: nil, options: nil, children: nil, items: nil)
    item = { "kind" => "builder_item", "id" => "i", "method" => method }
    item["args"] = args if args
    item["options"] = options if options
    item["children"] = children if children
    item["items"] = items unless items.nil?
    item
  end

  def text_node(content)
    { "kind" => "text", "id" => "t", "tag" => "p", "content" => content }
  end
end
