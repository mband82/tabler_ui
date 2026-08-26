# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor/renderer"
require "tabler_ui/docs/editor/contract"
require "tabler_ui/docs/editor/builder_map"
require "tabler_ui/docs/navigation"

# `type: :component` pulls in spec/support/component_helper.rb's
# #tabler_ui_view_context (config.include ComponentHelper, type: :component
# in spec/rails_helper.rb) -- the same real ActionView::Base + TablerUi::Helper
# wiring every component spec renders through, so the Renderer under test
# dispatches through the exact same `tabler_ui.<name>(...)` path a host app's
# ERB uses. spec/lib/tabler_ui/docs/demo_registry_spec.rb needs the *docs*
# engine's view path too (for its own "tabler_ui/docs/demos/demo" partial);
# this spec only ever renders real tabler_ui/<name>/component partials, so
# ComponentHelper's narrower view path (just the main engine) is enough.
RSpec.describe TablerUi::Docs::Editor::Renderer, type: :component do
  let(:view) { tabler_ui_view_context }

  def renderer(resolve: nil)
    described_class.new(view, resolve: resolve)
  end

  def frag(html)
    Nokogiri::HTML5.fragment(html)
  end

  # --- Contract-shaped node builders --------------------------------------

  def component_node(name, id, args: {}, options: {}, items: nil, slots: nil, html: {})
    node = { "kind" => "component", "id" => id, "name" => name, "args" => args, "options" => options, "html" => html }
    node["items"] = items if items
    node["slots"] = slots if slots
    node
  end

  # Regression: Tree normalizes every Hash key at every depth to a String,
  # but components read structured option values with Symbol keys --
  # datagrid's template does item[:title]. Symbolizing only the option's own
  # top-level key left a String-keyed Hash reaching the component, so every
  # lookup returned nil and the preview rendered blank while the ERB
  # ErbGenerator exported (which emits real Symbol keys) rendered correctly.
  # The preview lying about the export is the worst failure this feature has;
  # found by the renderer/generator equivalence corpus, not by either
  # module's own specs.
  describe "structured option values" do
    it "deep-symbolizes label-shaped keys inside Hash and Array-of-Hash options" do
      node = component_node("datagrid", "dg1",
                            options: { "items" => [{ "title" => "Owner", "content" => "Ada Lovelace" }] })

      html = renderer.render(node).to_s

      expect(html).to include("Owner")
      expect(html).to include("Ada Lovelace")
    end
  end

  # --- table :columns synthesis -------------------------------------------

  # A design tree is JSON, so table's real `value:` callable per column
  # can't survive the trip -- the tree carries a declarative `key:` instead
  # and Renderer#synthesize_table_columns builds the real Proc from it right
  # before dispatch. See erb_generator_spec.rb's mirror-image coverage of
  # the export side, and consistency_spec.rb's fixture for the end-to-end
  # (preview == rendered export) guarantee.
  describe "table :columns synthesis" do
    it "renders real header text and cell values from a declarative key:" do
      node = component_node("table", "t1",
                            options: {
                              "columns" => [{ "label" => "Name", "key" => "name" }],
                              "data" => [{ "name" => "Ada Lovelace" }, { "name" => "Grace Hopper" }]
                            })

      doc = frag(renderer.render(node))

      expect(doc.css("th").map(&:text)).to eq(["Name"])
      expect(doc.css("td").map(&:text)).to eq(["Ada Lovelace", "Grace Hopper"])
    end

    it "reads the row by the SAME key deep_symbolize would have already turned into a Symbol -- " \
       "a String-vs-Symbol mismatch here would silently render every cell blank" do
      # "name" is RUBY_LABEL-shaped, so by the time #component_opts calls
      # #synthesize_table_columns, deep_symbolize has already turned every
      # row's "name" key into the Symbol :name. If the synthesized lambda
      # looked row up by the String "name" instead, row["name"] would miss
      # and every cell would render blank rather than erroring -- the kind
      # of silent wrong-output bug a positive assertion here (not just
      # "doesn't raise") is required to catch.
      node = component_node("table", "t1",
                            options: {
                              "columns" => [{ "label" => "Name", "key" => "name" }],
                              "data" => [{ "name" => "Ada" }]
                            })

      html = renderer.render(node).to_s

      expect(html).to include("Ada")
      expect(html).not_to include("<td></td>")
    end

    it "leaves a column alone when it already carries a real callable :value " \
       "(a node built by hand, not from Tree/JSON)" do
      node = component_node("table", "t1",
                            options: {
                              "columns" => [{ "label" => "Name", "value" => ->(row) { row[:name].upcase } }],
                              "data" => [{ "name" => "Ada" }]
                            })

      html = renderer.render(node).to_s

      expect(html).to include("ADA")
    end

    it "renders an error marker, not a NoMethodError, for a column with neither key: nor a callable value:" do
      node = component_node("table", "t1",
                            options: { "columns" => [{ "label" => "Name" }], "data" => [{ "name" => "Ada" }] })

      doc = frag(renderer.render(node))

      marker = doc.at_css('[data-editor-node-id="t1"]')
      expect(marker["class"]).to eq("alert alert-danger")
      expect(marker.text).to include("key")
    end

    it "drops the editor-only key: before handing options to the real dispatcher (harmless either way, " \
       "but keeps the two sides in agreement -- see ErbGenerator#format_column_entry)" do
      node = component_node("table", "t1",
                            options: { "columns" => [{ "label" => "Name", "key" => "name" }], "data" => [] })

      html = renderer.render(node).to_s

      expect(html).not_to include("alert alert-danger")
    end

    it "does nothing to a non-table component's own Array<Hash> option (datagrid's :items has no :key concept)" do
      node = component_node("datagrid", "dg1", options: { "items" => [{ "title" => "Owner", "content" => "Ada" }] })

      expect { renderer.render(node) }.not_to raise_error
    end
  end

  def builder_item(id, method, args: {}, options: {}, items: nil, children: nil, html: {})
    node = { "kind" => "builder_item", "id" => id, "method" => method, "args" => args, "options" => options,
             "html" => html }
    node["items"] = items if items
    node["children"] = children if children
    node
  end

  def row_node(id, children: [], attrs: {})
    { "kind" => "row", "id" => id, "attrs" => attrs, "children" => children }
  end

  def column_node(id, span:, children: [], attrs: {})
    { "kind" => "column", "id" => id, "span" => span, "attrs" => attrs, "children" => children }
  end

  def heading_node(id, content:, level: 2)
    { "kind" => "heading", "id" => id, "level" => level, "content" => content }
  end

  def text_node(id, content:, tag: "p")
    { "kind" => "text", "id" => id, "tag" => tag, "content" => content }
  end

  def fragment_node(id, children: [])
    { "kind" => "fragment", "id" => id, "children" => children }
  end

  def partial_node(id, path:)
    { "kind" => "partial", "id" => id, "path" => path }
  end

  # --- Each node kind renders ---------------------------------------------

  describe "node kinds" do
    it "renders a fragment as just its children, with no wrapper element" do
      tree = fragment_node("f1", children: [text_node("t1", content: "Hello")])
      html = renderer.render(tree)

      expect(html).to eq('<p data-editor-node-id="t1" data-editor-field="content">Hello</p>')
    end

    it "renders a row as a plain div.row carrying the marker, wrapping its children" do
      tree = row_node("r1", children: [text_node("t1", content: "Inside")])
      doc = frag(renderer.render(tree))
      row = doc.at_css('div[data-editor-node-id="r1"]')

      expect(row["class"]).to eq("row")
      expect(row.at_css("p").text).to eq("Inside")
    end

    it "renders a column's span as base/breakpoint col-* classes" do
      tree = column_node("c1", span: { "base" => 12, "md" => 6 })
      doc = frag(renderer.render(tree))
      col = doc.at_css('div[data-editor-node-id="c1"]')

      expect(col["class"]).to eq("col-12 col-md-6")
    end

    it "renders a column with no span as a bare .col" do
      doc = frag(renderer.render(column_node("c2", span: {})))
      expect(doc.at_css('div[data-editor-node-id="c2"]')["class"]).to eq("col")
    end

    it "renders heading as h<level>, stamped with the node id and editor-field" do
      doc = frag(renderer.render(heading_node("h1", content: "Title", level: 3)))
      h = doc.at_css("h3")

      expect(h.text).to eq("Title")
      expect(h["data-editor-node-id"]).to eq("h1")
      expect(h["data-editor-field"]).to eq("content")
    end

    it "renders text using its own tag, defaulting to <p>" do
      doc = frag(renderer.render(text_node("x1", content: "Body", tag: "small")))
      expect(doc.at_css("small").text).to eq("Body")
    end

    it "renders a component node through the real dispatcher" do
      doc = frag(renderer.render(component_node("badge", "b1", options: { "text" => "New" })))
      badge = doc.at_css('span[data-editor-node-id="b1"]')

      expect(badge["class"]).to include("badge")
      expect(badge.text.strip).to eq("New")
    end

    it "recurses into a resolved partial, without ever calling Rails' render on the path" do
      target = text_node("resolved-t", content: "From partial")
      resolve = ->(path) { path == "shared/_header.html.erb" ? fragment_node("frag", children: [target]) : nil }

      doc = frag(renderer(resolve: resolve).render(partial_node("p1", path: "shared/_header.html.erb")))
      expect(doc.at_css('p[data-editor-node-id="resolved-t"]').text).to eq("From partial")
    end

    it "renders an error marker for a partial that resolve: can't resolve (nil resolve:)" do
      doc = frag(renderer.render(partial_node("p2", path: "unknown/_thing.html.erb")))
      marker = doc.at_css('div[data-editor-node-id="p2"]')

      expect(marker["class"]).to eq("alert alert-danger")
      expect(marker.text).to include("unresolved partial")
    end

    it "renders an error marker for a partial when resolve: returns nil" do
      doc = frag(renderer(resolve: ->(_path) { nil }).render(partial_node("p3", path: "x.html.erb")))
      expect(doc.at_css('div[data-editor-node-id="p3"]').text).to include("unresolved partial")
    end
  end

  # --- The 35-component marker sweep --------------------------------------

  describe "the html: hook marker (rule 5 conformance)" do
    # The 8 components with a mandatory positional -- Contract's `args`,
    # keyed by parameter name.
    REQUIRED_ARGS = {
      "accordion" => { "id" => "acc-x" },
      "carousel" => { "id" => "car-x" },
      "icon" => { "icon" => "home" },
      "illustration" => { "name" => "boy" },
      "modal" => { "id" => "modal-x" },
      "offcanvas" => { "id" => "off-x" },
      "settings_page" => { "id" => "sp-x" },
      "tabs" => { "id" => "tabs-x" }
    }.freeze

    # One minimal, valid item per builder-style component (all 11 except
    # navbar, which is exercised separately -- see "navbar's full
    # three-level chain" below) so the sweep renders REAL markup (and so
    # actually exercises the html: hook) instead of tripping a builder's
    # own validate! hook (e.g. steps' current: bounds check against zero
    # items) into an unrelated error marker.
    ITEM_FOR = {
      "accordion" => %w[item title],
      "breadcrumb" => %w[item title],
      "carousel" => %w[item],
      "datagrid" => %w[item title],
      "dropdown" => %w[item title],
      "pagination" => %w[item page],
      "settings_page" => %w[item title],
      "steps" => %w[item title],
      "tabs" => %w[tab title],
      "timeline" => %w[item]
    }.freeze

    def minimal_items_for(name)
      return nil unless ITEM_FOR.key?(name)

      method, arg_name = ITEM_FOR.fetch(name)
      args = arg_name == "page" ? { "page" => 1 } : (arg_name ? { arg_name => "Item" } : {})
      [builder_item("item-#{name}", method, args: args)]
    end

    def minimal_navbar_items
      [
        builder_item("nav-left", "left", items: [
                       builder_item("nav-add", "add", args: { "title" => "Home" }, options: { "url" => "/", "active" => false })
                     ])
      ]
    end

    it "lands data-editor-node-id on every one of the 35 components' root element" do
      failures = []

      TablerUi::Docs::Navigation.components.each do |name|
        args = REQUIRED_ARGS.fetch(name, {})
        items = name == "navbar" ? minimal_navbar_items : minimal_items_for(name)

        node = component_node(name, "sweep-#{name}", args: args, items: items)
        html = renderer.render(node).to_s

        marker_present = html.include?(%(data-editor-node-id="sweep-#{name}"))
        errored = html.include?("alert alert-danger")

        failures << "#{name}: rendered an error marker instead of real markup (#{html})" if errored
        failures << "#{name}: html: hook did not stamp data-editor-node-id on the root element" if !errored && !marker_present
      end

      expect(failures).to be_empty, failures.join("\n")
    end

    it "renders the 8 components with a required positional from their node's args" do
      REQUIRED_ARGS.each do |name, args|
        node = component_node(name, "req-#{name}", args: args)
        html = renderer.render(node).to_s

        expect(html).not_to include("alert alert-danger"), "#{name} failed to render from args: #{args.inspect} -- #{html}"
        expect(html).to include(%(data-editor-node-id="req-#{name}"))
      end
    end
  end

  # --- Nested slots ---------------------------------------------------------

  describe "slot-style components" do
    it "recurses design-tree children into each named slot" do
      node = component_node(
        "card", "card1",
        options: { "title" => "My Card" },
        slots: {
          "body" => [row_node("body-row", children: [text_node("body-text", content: "Body content")])],
          "footer" => [text_node("footer-text", content: "Footer")]
        }
      )

      doc = frag(renderer.render(node))
      expect(doc.at_css(".card-body p").text).to eq("Body content")
      expect(doc.at_css(".card-footer").text.strip).to eq("Footer")
      expect(doc.at_css('[data-editor-node-id="body-row"]')).not_to be_nil
      expect(doc.at_css('[data-editor-node-id="footer-text"]')).not_to be_nil
    end

    it "gives no block at all to a slot-capable component whose node has no slots" do
      # Guards against TablerUi::Ui's own guard_discarded_block! (a block
      # that writes content but sets no slot raises ArgumentError) --
      # rendering must not raise just because a card has nothing in it.
      node = component_node("card", "card2", options: { "title" => "Empty" })
      expect { renderer.render(node) }.not_to raise_error
    end
  end

  # --- Builder-style items ---------------------------------------------------

  describe "builder-style components" do
    it "emits every item in order, each carrying its own marker" do
      node = component_node("tabs", "tabsx", args: { "id" => "tabsx" }, items: [
                               builder_item("tab-a", "tab", args: { "title" => "First" }),
                               builder_item("tab-b", "tab", args: { "title" => "Second" },
                                                            children: [text_node("tab-b-body", content: "Second body")])
                             ])

      doc = frag(renderer.render(node))
      links = doc.css("a.nav-link")

      expect(links.map { |l| l.text.strip }).to eq(%w[First Second])
      expect(doc.at_css('a[data-editor-node-id="tab-a"]')).not_to be_nil
      expect(doc.at_css('a[data-editor-node-id="tab-b"]')).not_to be_nil
      expect(doc.at_css('[data-editor-node-id="tab-b-body"]').text).to eq("Second body")
    end

    it "navbar's full three-level chain: left -> dropdown -> item" do
      node = component_node("navbar", "navchain", items: [
                               builder_item("navleft", "left", items: [
                                              builder_item("dd", "dropdown", args: { "title" => "Admin" }, items: [
                                                             builder_item("dd-item", "item",
                                                                          args: { "title" => "Users" },
                                                                          options: { "url" => "/users", "active" => false }),
                                                             builder_item("dd-div", "divider"),
                                                             builder_item("dd-item-2", "item",
                                                                          args: { "title" => "Settings" },
                                                                          options: { "url" => "/settings", "active" => false })
                                                           ])
                                            ])
                             ])

      doc = frag(renderer.render(node))
      expect(doc.at_css("a.dropdown-toggle").text.strip).to eq("Admin")
      # A leading/trailing divider is trimmed by the navbar template itself
      # (see the `drop_while`s in _nav_item.html.erb) -- a 2nd item keeps
      # this one interior so it actually renders, proving #emit_items walked
      # all three siblings in order.
      expect(doc.at_css(".dropdown-divider")).not_to be_nil

      # This used to assert data-editor-node-id was nil on the "Users" link,
      # documenting a real HTML-attribute gap this test found: unlike every
      # other builder item, Navbar::Component::NavigationGroup::DropDownProxy#item
      # stored only `link_html:` on its Item Struct and had no root part for
      # the id stamp to land on. That gap has since been closed in
      # app/components/tabler_ui/navbar/component.rb (#item, #divider and
      # #header all take `html:` now), so the placeholder becomes the real
      # assertion it was left here to become: every nested dropdown item is
      # selectable in the editor like any other node.
      expect(doc.css(".dropdown-item").map { |a| a.text.strip }).to eq(%w[Users Settings])
      expect(doc.css(".dropdown-item").first["data-editor-node-id"]).to eq("dd-item")
    end
  end

  # --- Error isolation --------------------------------------------------------

  describe "error handling" do
    it "replaces a node that raises with a marker, without affecting its siblings" do
      tree = fragment_node("root", children: [
                              component_node("badge", "ok1", options: { "text" => "First" }),
                              component_node("badge", "bad", options: { "text" => "Bad", "color" => "not-a-real-color" }),
                              component_node("badge", "ok2", options: { "text" => "Third" })
                            ])

      doc = frag(renderer.render(tree))

      expect(doc.at_css('[data-editor-node-id="ok1"]').text.strip).to eq("First")
      expect(doc.at_css('[data-editor-node-id="ok2"]').text.strip).to eq("Third")

      bad = doc.at_css('[data-editor-node-id="bad"]')
      expect(bad["class"]).to eq("alert alert-danger")
      expect(bad.text).to include("badge")
    end

    it "replaces a builder-style component whose validate! hook fails with a single marker" do
      # steps' current: bounds check (validate!) only runs after the block,
      # once every item is known -- current: 5 with only one item raises.
      tree = fragment_node("root", children: [
                              component_node("badge", "before", options: { "text" => "Before" }),
                              component_node("steps", "broken", options: { "current" => 5 }, items: [
                                               builder_item("only-step", "item", args: { "title" => "Step 1" })
                                             ]),
                              component_node("badge", "after", options: { "text" => "After" })
                            ])

      doc = frag(renderer.render(tree))
      expect(doc.at_css('[data-editor-node-id="before"]').text.strip).to eq("Before")
      expect(doc.at_css('[data-editor-node-id="broken"]')["class"]).to eq("alert alert-danger")
      expect(doc.at_css('[data-editor-node-id="after"]').text.strip).to eq("After")
    end

    it "renders an error marker for an unknown node kind instead of raising" do
      doc = frag(renderer.render({ "kind" => "bogus", "id" => "bx" }))
      expect(doc.at_css('[data-editor-node-id="bx"]')["class"]).to eq("alert alert-danger")
    end
  end

  # --- contenteditable is never emitted ---------------------------------------

  describe "contenteditable" do
    it "never appears anywhere in rendered output" do
      tree = fragment_node("root", children: [
                              heading_node("h", content: "Title"),
                              text_node("t", content: "Body"),
                              component_node("tabs", "tabsy", args: { "id" => "tabsy" }, items: [
                                               builder_item("tab1", "tab", args: { "title" => "Tab" },
                                                                    children: [text_node("tb", content: "Content")])
                                             ]),
                              component_node("card", "cardy", slots: { "body" => [text_node("cb", content: "Card body")] })
                            ])

      html = renderer.render(tree).to_s
      expect(html.downcase).not_to include("contenteditable")
    end
  end

  # --- Text content is always escaped -----------------------------------------

  describe "text content escaping" do
    it "escapes heading content instead of rendering it as markup" do
      html = renderer.render(heading_node("h", content: "<script>alert(1)</script>")).to_s

      expect(html).not_to include("<script>")
      expect(frag(html).at_css("h2").text).to eq("<script>alert(1)</script>")
    end

    it "escapes text content instead of rendering it as markup" do
      html = renderer.render(text_node("t", content: "<img src=x onerror=alert(1)>")).to_s

      expect(html).not_to include("<img")
      expect(frag(html).at_css("p").text).to eq("<img src=x onerror=alert(1)>")
    end
  end

  # --- Depth guard (defense in depth) -----------------------------------------

  describe "depth guard" do
    def deep_row_chain(depth, id_prefix: "row")
      node = row_node("#{id_prefix}#{depth}")
      return node if depth <= 1

      row_node("#{id_prefix}#{depth}", children: [deep_row_chain(depth - 1, id_prefix: id_prefix)])
    end

    it "does not raise SystemStackError and substitutes a marker past Contract::LIMITS[:depth]" do
      max_depth = TablerUi::Docs::Editor::Contract::LIMITS.fetch(:depth)
      tree = deep_row_chain(max_depth + 8)

      html = nil
      expect { html = renderer.render(tree).to_s }.not_to raise_error
      expect(html).to include("exceeds max depth")
    end

    it "renders normally well within the depth limit" do
      max_depth = TablerUi::Docs::Editor::Contract::LIMITS.fetch(:depth)
      tree = deep_row_chain(max_depth - 4)

      html = renderer.render(tree).to_s
      expect(html).not_to include("alert alert-danger")
    end
  end
end
