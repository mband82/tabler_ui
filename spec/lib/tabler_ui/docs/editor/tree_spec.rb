# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor"
require "tabler_ui/docs/editor/tree"

# Tree is the security boundary for the design editor: every payload here is
# treated as attacker-controlled. The suite is organised the same way the
# class's own header comment is -- structural rules first, then the
# injection/security matrix CLAUDE.md's brief specifically calls out, then
# the numeric limits, then "never raises on garbage".
#
# TablerUi.auth_method (lib/tabler_ui.rb) is order-dependent global state
# other spec files mutate -- see that file's own comment. Nothing in this
# suite reads or writes it (Tree only ever *reports* the string "auth", it
# never calls TablerUi::Authorization), so no around block is needed here,
# but every example below is written to stand on its own regardless of
# --seed / run order.
RSpec.describe TablerUi::Docs::Editor::Tree do
  Contract = TablerUi::Docs::Editor::Contract

  def node(kind, id, extra = {})
    { "kind" => kind, "id" => id }.merge(extra)
  end

  def fragment(id, children = [])
    node("fragment", id, "children" => children)
  end

  def row(id, children = [], attrs = {})
    node("row", id, "children" => children, "attrs" => attrs)
  end

  def column(id, children = [], span = {})
    node("column", id, "children" => children, "span" => span)
  end

  def heading(id, level = 2, content = "Hello")
    node("heading", id, "level" => level, "content" => content)
  end

  def text(id, tag = "p", content = "Hello")
    node("text", id, "tag" => tag, "content" => content)
  end

  def component(id, name, extra = {})
    node("component", id, { "name" => name }.merge(extra))
  end

  def partial(id, path)
    node("partial", id, "path" => path)
  end

  def builder_item(id, method, extra = {})
    node("builder_item", id, { "method" => method }.merge(extra))
  end

  def call(raw)
    described_class.call(raw)
  end

  # --- Valid trees of each kind normalize cleanly ---------------------------

  describe "valid trees" do
    it "normalizes a bare fragment root" do
      result = call(fragment("root1"))

      expect(result.fatal?).to be false
      expect(result.errors).to eq([])
      expect(result.node).to eq("kind" => "fragment", "id" => "root1", "children" => [])
    end

    it "normalizes heading and text nodes" do
      result = call(fragment("f1", [heading("h1", 3, "Title"), text("t1", "span", "Body")]))

      expect(result.errors).to eq([])
      expect(result.node["children"]).to eq(
        [
          { "kind" => "heading", "id" => "h1", "level" => 3, "content" => "Title" },
          { "kind" => "text", "id" => "t1", "tag" => "span", "content" => "Body" }
        ]
      )
    end

    it "normalizes row > column nesting with span and attrs" do
      tree = fragment("f1", [
                row("r1", [column("c1", [text("t1")], { "base" => 12, "md" => 6 })], { "class" => "gx-2" })
              ])
      result = call(tree)

      expect(result.errors).to eq([])
      col = result.node["children"].first["children"].first
      expect(col).to include("kind" => "column", "span" => { "base" => 12, "md" => 6 })
    end

    it "normalizes a slot-style component (card) with a slotted child" do
      tree = fragment("f1", [
                component("c1", "card",
                           "options" => { "title" => "Hi" },
                           "slots" => { "body" => [text("t1")] })
              ])
      result = call(tree)

      expect(result.errors).to eq([])
      comp = result.node["children"].first
      expect(comp["name"]).to eq("card")
      expect(comp["options"]).to eq("title" => "Hi")
      expect(comp["slots"]["body"]).to eq([{ "kind" => "text", "id" => "t1", "tag" => "p", "content" => "Hello" }])
      expect(comp).not_to have_key("items")
    end

    it "normalizes a component with a required positional arg (modal's id)" do
      tree = fragment("f1", [component("c1", "modal", "args" => { "id" => "my-modal" }, "options" => { "title" => "x" })])
      result = call(tree)

      expect(result.errors).to eq([])
      expect(result.node["children"].first["args"]).to eq("id" => "my-modal")
    end

    it "normalizes a component enum option to a Symbol when EnumMap says so (dropdown's align:)" do
      tree = fragment("f1", [component("c1", "dropdown", "options" => { "align" => "end" })])
      result = call(tree)

      expect(result.errors).to eq([])
      expect(result.node["children"].first["options"]["align"]).to eq(:end)
    end

    it "normalizes html: (root) and a documented <part>_html: on a component" do
      tree = fragment("f1", [
                component("c1", "card", "html" => { "root" => { "class" => "mb-4" }, "header" => { "class" => "bg-dark" } })
              ])
      result = call(tree)

      expect(result.errors).to eq([])
      expect(result.node["children"].first["html"]).to eq(
        "root" => { "class" => "mb-4" }, "header" => { "class" => "bg-dark" }
      )
    end

    it "normalizes a partial node" do
      result = call(fragment("f1", [partial("p1", "shared/_header.html.erb")]))

      expect(result.errors).to eq([])
      expect(result.node["children"]).to eq([{ "kind" => "partial", "id" => "p1", "path" => "shared/_header.html.erb" }])
    end

    it "normalizes a builder-style component (tabs) with an items array" do
      tree = fragment("f1", [
                component("c1", "tabs", "args" => { "id" => "tabset" },
                                        "items" => [builder_item("b1", "tab", "args" => { "title" => "One" })])
              ])
      result = call(tree)

      expect(result.errors).to eq([])
      comp = result.node["children"].first
      expect(comp).not_to have_key("slots")
      expect(comp["items"]).to eq(
        [{ "kind" => "builder_item", "id" => "b1", "method" => "tab", "args" => { "title" => "One" },
           "options" => {}, "html" => {}, "children" => [] }]
      )
    end
  end

  # --- Injection: component name allowlist -----------------------------------

  describe "component name injection" do
    %w[../../etc/passwd layouts/application foo/bar Card].each do |bad_name|
      it "rejects #{bad_name.inspect} without raising" do
        result = nil
        expect { result = call(fragment("f1", [component("c1", bad_name)])) }.not_to raise_error

        expect(result.fatal?).to be false
        expect(result.node["children"]).to eq([])
        expect(result.errors).to include(a_string_matching(/unknown or invalid component name/))
      end
    end

    it "rejects an empty component name without raising" do
      result = nil
      expect { result = call(fragment("f1", [component("c1", "")])) }.not_to raise_error

      expect(result.node["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/unknown or invalid component name/))
    end

    it "never even attempts to constantize a name outside Navigation.components, even if shape-valid" do
      result = call(fragment("f1", [component("c1", "not_a_real_component")]))

      expect(result.node["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/unknown or invalid component name/))
    end
  end

  # --- Unknown option key ------------------------------------------------------

  describe "unknown option key" do
    it "is dropped with a warning, and the rest of the tree stays usable" do
      tree = fragment("f1", [component("c1", "card", "options" => { "title" => "Hi", "bogus_key" => "x" })])
      result = call(tree)

      expect(result.fatal?).to be false
      comp = result.node["children"].first
      expect(comp["options"]).to eq("title" => "Hi")
      expect(result.errors).to include(a_string_matching(/warning:.*bogus_key.*unknown option/))
    end
  end

  # Renderer and ErbGenerator disagree on a table column carrying neither
  # key: nor a callable value: -- Renderer isolates it into an inline marker,
  # ErbGenerator raises. A raise escapes the preview endpoint as a failed
  # request rather than a rendered design, so this class rejects the shape
  # once, up front, and both downstream walkers only ever see trees they
  # agree on. Verified end to end: before this rule, that exact tree returned
  # Rails' HTML exception page from POST /ui/editor/preview.
  describe "table's declarative columns" do
    it "drops a column with neither key: nor value:, reporting why, and keeps the good ones" do
      tree = fragment("f1", [component("c1", "table", "options" => {
                                         "columns" => [{ "label" => "Name", "key" => "name" },
                                                       { "label" => "Orphan" }],
                                         "data" => [{ "name" => "Ada" }]
                                       })])
      result = call(tree)

      expect(result.fatal?).to be false
      expect(result.node["children"].first["options"]["columns"])
        .to eq([{ "label" => "Name", "key" => "name" }])
      expect(result.errors).to include(a_string_matching(/columns\[1\].*key:/))
    end

    it "removes the option entirely when no column survives, rather than leaving an empty Array" do
      tree = fragment("f1", [component("c1", "table", "options" => { "columns" => [{ "label" => "Orphan" }] })])
      result = call(tree)

      expect(result.node["children"].first["options"]).not_to have_key("columns")
    end
  end

  # --- auth stripped everywhere -----------------------------------------------

  describe "'auth' is forbidden everywhere, always reported as an error (never silently dropped)" do
    it "is stripped from a component's options" do
      tree = fragment("f1", [component("c1", "card", "options" => { "title" => "Hi", "auth" => :manage })])
      result = call(tree)

      expect(result.node["children"].first["options"]).to eq("title" => "Hi")
      expect(result.errors).to include(a_string_matching(/forbidden option stripped/))
    end

    it "is stripped from a component's args" do
      tree = fragment("f1", [component("c1", "modal", "args" => { "id" => "m1", "auth" => :manage })])
      result = call(tree)

      expect(result.node["children"].first["args"]).to eq("id" => "m1")
      expect(result.errors).to include(a_string_matching(/forbidden option stripped/))
    end

    it "is stripped from html: attrs" do
      tree = fragment("f1", [component("c1", "card", "html" => { "root" => { "class" => "x", "auth" => "y" } })])
      result = call(tree)

      expect(result.node["children"].first["html"]).to eq("root" => { "class" => "x" })
      expect(result.errors).to include(a_string_matching(/forbidden option stripped/))
    end

    it "is stripped from a nested data:/aria: attribute hash" do
      tree = fragment("f1", [component("c1", "card", "html" => { "root" => { "data" => { "auth" => "y" } } })])
      result = call(tree)

      expect(result.node["children"].first["html"]).to eq("root" => { "data" => {} })
      expect(result.errors).to include(a_string_matching(/forbidden option stripped/))
    end

    it "is stripped from a nested builder_item's options" do
      tree = fragment("f1", [
                component("c1", "navbar",
                           "items" => [
                             builder_item("left1", "left",
                                          "items" => [builder_item("add1", "add",
                                                                    "args" => { "title" => "Home" },
                                                                    "options" => { "url" => "/", "auth" => :manage })])
                           ])
              ])
      result = call(tree)

      add_item = result.node["children"].first["items"].first["items"].first
      expect(add_item["options"]).to eq("url" => "/")
      expect(result.errors).to include(a_string_matching(/forbidden option stripped/))
    end

    it "is stripped from an option value nested inside a Hash-shaped option" do
      tree = fragment("f1", [component("c1", "navbar", "options" => { "link_html" => { "class" => "x", "auth" => "y" } })])
      result = call(tree)

      expect(result.node["children"].first["options"]["link_html"]).to eq("class" => "x")
      expect(result.errors).to include(a_string_matching(/forbidden option stripped/))
    end
  end

  # --- Limits ------------------------------------------------------------------

  describe "limits" do
    def count_nodes(n)
      return 0 unless n.is_a?(Hash)

      1 + (n["children"] || []).sum { |c| count_nodes(c) }
    end

    it "drops nodes beyond LIMITS[:nodes] and reports it exactly once" do
      # Spread across several rows, each within children_per_node, so it's
      # the *global* node budget being exercised here, not the per-node
      # children cap (a separate limit, tested below).
      rows = 10.times.map do |r|
        children = Contract::LIMITS[:children_per_node].times.map { |i| text("t#{r}_#{i}") }
        row("r#{r}", children)
      end
      result = call(fragment("f1", rows))

      expect(result.fatal?).to be false
      expect(count_nodes(result.node)).to eq(Contract::LIMITS[:nodes])
      expect(result.errors.count { |e| e.include?("exceeds the maximum of #{Contract::LIMITS[:nodes]} nodes") }).to eq(1)
    end

    it "rejects a node past the max nesting depth, without stack overflow" do
      innermost = text("deep")
      wrapped = (Contract::LIMITS[:depth] + 5).times.reduce(innermost) { |child, i| row("r#{i}", [column("col#{i}", [child])]) }
      result = call(fragment("f1", [wrapped]))

      expect(result.fatal?).to be false
      expect(result.errors).to include(a_string_matching(/exceeds the maximum nesting depth/))
    end

    it "caps options_per_node, dropping the extras with a warning" do
      many_options = (Contract::LIMITS[:options_per_node] + 10).times.to_h { |i| ["opt#{i}", "v"] }
      tree = fragment("f1", [component("c1", "card", "options" => many_options)])
      result = call(tree)

      expect(result.errors).to include(a_string_matching(/exceeds the #{Contract::LIMITS[:options_per_node]} limit/))
    end

    it "caps children_per_node, dropping the extras with a warning" do
      many_children = (Contract::LIMITS[:children_per_node] + 10).times.map { |i| text("t#{i}") }
      result = call(fragment("f1", many_children))

      expect(result.node["children"].length).to eq(Contract::LIMITS[:children_per_node])
      expect(result.errors).to include(a_string_matching(/exceeds the #{Contract::LIMITS[:children_per_node]} limit/))
    end

    it "caps an over-long content string" do
      long = "x" * (Contract::LIMITS[:string] + 100)
      result = call(fragment("f1", [text("t1", "p", long)]))

      expect(result.node["children"].first["content"].length).to eq(Contract::LIMITS[:string])
      expect(result.errors).to include(a_string_matching(/truncated/))
    end

    it "caps an over-long attribute string value" do
      long = "x" * (Contract::LIMITS[:attr_string] + 100)
      tree = fragment("f1", [row("r1", [], { "class" => long })])
      result = call(tree)

      expect(result.node["children"].first["attrs"]["class"].length).to eq(Contract::LIMITS[:attr_string])
      expect(result.errors).to include(a_string_matching(/truncated/))
    end
  end

  # --- Attribute rejection -------------------------------------------------------

  describe "attribute rejection" do
    %w[onclick href style srcdoc].each do |bad_key|
      it "rejects the '#{bad_key}' attribute key" do
        tree = fragment("f1", [row("r1", [], { bad_key => "x" })])
        result = call(tree)

        expect(result.node["children"].first["attrs"]).to eq({})
        expect(result.errors).to include(a_string_matching(/attribute key is not allowed/))
      end
    end

    %w[javascript:alert(1) vbscript:msgbox(1)].each do |bad_value|
      it "rejects the dangerous attribute value #{bad_value.inspect}" do
        tree = fragment("f1", [row("r1", [], { "title" => bad_value })])
        result = call(tree)

        expect(result.node["children"].first["attrs"]).to eq({})
        expect(result.errors).to include(a_string_matching(/dangerous value pattern/))
      end
    end

    it "rejects a dangerous content string on heading/text outright (drops the node)" do
      result = call(fragment("f1", [text("t1", "p", "javascript:alert(1)")]))

      expect(result.node["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/dangerous value pattern/))
    end
  end

  # --- slots vs items mutual exclusion -------------------------------------------

  describe "slots vs. items" do
    it "rejects slots on a builder-style component" do
      tree = fragment("f1", [component("c1", "tabs", "args" => { "id" => "t1" }, "slots" => { "body" => [] })])
      result = call(tree)

      comp = result.node["children"].first
      expect(comp).not_to have_key("slots")
      expect(comp["items"]).to eq([])
      expect(result.errors).to include(a_string_matching(/not valid on builder-style component/))
    end

    it "rejects items on a slot-style component" do
      tree = fragment("f1", [component("c1", "card", "items" => [builder_item("b1", "tab")])])
      result = call(tree)

      comp = result.node["children"].first
      expect(comp).not_to have_key("items")
      expect(comp["slots"]).to eq({})
      expect(result.errors).to include(a_string_matching(/not valid on slot-style component/))
    end

    it "rejects a component that sends both -- only the illegal one for its style is kept out" do
      tree = fragment("f1", [
                component("c1", "tabs", "args" => { "id" => "t1" },
                                        "slots" => { "body" => [] },
                                        "items" => [builder_item("b1", "tab", "args" => { "title" => "x" })])
              ])
      result = call(tree)

      comp = result.node["children"].first
      expect(comp).not_to have_key("slots")
      expect(comp["items"].length).to eq(1)
      expect(result.errors).to include(a_string_matching(/not valid on builder-style component/))
    end
  end

  # --- Navbar's three-level builder chain -----------------------------------------

  describe "navbar's full builder chain" do
    def full_navbar_tree
      component("nav1", "navbar",
                "items" => [
                  builder_item("left1", "left",
                               "items" => [
                                 builder_item("add1", "add", "args" => { "title" => "Home" }, "options" => { "url" => "/" }),
                                 builder_item("dd1", "dropdown", "args" => { "title" => "Admin" },
                                                                  "items" => [
                                                                    builder_item("h1", "header", "args" => { "title" => "Manage" }),
                                                                    builder_item("i1", "item", "args" => { "title" => "Users" },
                                                                                                "options" => { "url" => "/users" }),
                                                                    builder_item("div1", "divider")
                                                                  ])
                               ])
                ])
    end

    it "validates end to end" do
      result = call(fragment("f1", [full_navbar_tree]))

      expect(result.errors).to eq([])
      left = result.node["children"].first["items"].first
      expect(left["method"]).to eq("left")
      expect(left["items"].map { |i| i["method"] }).to eq(%w[add dropdown])
      dropdown = left["items"].last
      expect(dropdown["items"].map { |i| i["method"] }).to eq(%w[header item divider])
    end

    it "rejects a method that's legal at one level but not another" do
      # "item" only exists at the :dropdown level, not :root or :group.
      tree = component("nav1", "navbar", "items" => [builder_item("i1", "item", "args" => { "title" => "x" })])
      result = call(fragment("f1", [tree]))

      expect(result.node["children"].first["items"]).to eq([])
      expect(result.errors).to include(a_string_matching(/not a legal builder method/))
    end

    it "rejects a :group-level method nested one level too deep (inside a :dropdown)" do
      tree = component("nav1", "navbar",
                        "items" => [
                          builder_item("left1", "left",
                                       "items" => [
                                         builder_item("dd1", "dropdown", "args" => { "title" => "Admin" },
                                                                          "items" => [
                                                                            # "add" is a :group method, not legal at :dropdown level
                                                                            builder_item("bad1", "add", "args" => { "title" => "x" })
                                                                          ])
                                       ])
                        ])
      result = call(fragment("f1", [tree]))

      dropdown = result.node["children"].first["items"].first["items"].first
      expect(dropdown["items"]).to eq([])
      expect(result.errors).to include(a_string_matching(/not a legal builder method/))
    end
  end

  # --- row/column nesting -------------------------------------------------------

  describe "row/column nesting" do
    it "rejects a row directly inside a row" do
      tree = fragment("f1", [row("r1", [row("r2", [])])])
      result = call(tree)

      expect(result.node["children"].first["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/'row' is not allowed here/))
    end

    it "rejects a column that isn't a direct child of a row (under fragment)" do
      result = call(fragment("f1", [column("c1", [])]))

      expect(result.node["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/'column' is not allowed here/))
    end

    it "rejects a column that isn't a direct child of a row (under another column)" do
      tree = fragment("f1", [row("r1", [column("c1", [column("c2", [])])])])
      result = call(tree)

      col1 = result.node["children"].first["children"].first
      expect(col1["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/'column' is not allowed here/))
    end

    it "allows a column as a direct child of a row, and a row nested inside that column" do
      tree = fragment("f1", [row("r1", [column("c1", [row("r2", [])])])])
      result = call(tree)

      expect(result.errors).to eq([])
    end
  end

  # --- Duplicate ids -------------------------------------------------------------

  describe "duplicate node ids" do
    it "rejects the second occurrence of a duplicate id anywhere in the tree" do
      tree = fragment("f1", [text("dup"), heading("dup")])
      result = call(tree)

      expect(result.node["children"].length).to eq(1)
      expect(result.errors).to include(a_string_matching(/duplicate id/))
    end

    it "rejects a duplicate id even across very different node kinds and nesting depths" do
      tree = fragment("f1", [
                row("dup", [column("c1", [text("t1")])]),
                component("dup", "card")
              ])
      result = call(tree)

      expect(result.node["children"].length).to eq(1)
      expect(result.errors).to include(a_string_matching(/duplicate id/))
    end
  end

  # --- Garbage input never raises -------------------------------------------------

  describe "garbage input" do
    [nil, "a string", 42, true, [1, 2, 3], { "no" => "kind or id" }].each do |garbage|
      it "handles #{garbage.inspect} without raising, and reports fatal" do
        result = nil
        expect { result = call(garbage) }.not_to raise_error

        expect(result.fatal?).to be true
        expect(result.node).to be_nil
        expect(result.errors).not_to be_empty
      end
    end

    it "handles deeply wrong-shaped nested garbage without raising" do
      tree = { "kind" => "fragment", "id" => "f1", "children" => "not an array at all" }
      result = nil
      expect { result = call(tree) }.not_to raise_error

      expect(result.fatal?).to be false
      expect(result.node["children"]).to eq([])
    end

    it "handles a component node whose args/options/html are the wrong shape entirely" do
      tree = fragment("f1", [component("c1", "card", "args" => "nope", "options" => [1, 2], "html" => 5)])
      result = nil
      expect { result = call(tree) }.not_to raise_error

      comp = result.node["children"].first
      expect(comp["args"]).to eq({})
      expect(comp["options"]).to eq({})
      expect(comp["html"]).to eq({})
    end

    it "handles a builder_item with a garbage 'method' value without raising" do
      tree = component("nav1", "navbar", "items" => [builder_item("b1", { "not" => "a string" })])
      result = nil
      expect { result = call(fragment("f1", [tree])) }.not_to raise_error

      expect(result.node["children"].first["items"]).to eq([])
    end

    it "handles a self-referential-looking (but JSON-safe) deeply recursive Hash without raising" do
      raw = { "kind" => "fragment", "id" => "f1" }
      current = raw
      30.times do |i|
        child = { "kind" => "row", "id" => "r#{i}", "children" => [] }
        current["children"] = [child]
        current = child
      end

      expect { call(raw) }.not_to raise_error
    end
  end

  # --- id shape / kind membership -------------------------------------------------

  describe "basic node shape" do
    it "rejects an invalid id" do
      result = call(fragment("Not Valid!!"))

      expect(result.fatal?).to be true
    end

    it "rejects an unrecognised kind" do
      result = call(node("bogus_kind", "f1"))

      expect(result.fatal?).to be true
      expect(result.errors).to include(a_string_matching(/missing or unrecognised kind/))
    end

    it "rejects a nested fragment (fragment is root-only)" do
      tree = fragment("f1", [fragment("f2")])
      result = call(tree)

      expect(result.node["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/'fragment' is not allowed here/))
    end

    it "rejects a builder_item outside of an items array" do
      tree = fragment("f1", [builder_item("b1", "tab")])
      result = call(tree)

      expect(result.node["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/'builder_item' is not allowed here/))
    end
  end

  # --- partial path shape ----------------------------------------------------------

  describe "partial path" do
    it "accepts a nested valid path" do
      result = call(fragment("f1", [partial("p1", "shared/widgets/_footer.html.erb")]))

      expect(result.errors).to eq([])
    end

    %w[../etc/passwd _x.html.erb/../../y.html.erb /leading/slash.html.erb no_suffix
       shared/_header.html shared//double_slash.html.erb].each do |bad_path|
      it "rejects #{bad_path.inspect}" do
        result = call(fragment("f1", [partial("p1", bad_path)]))

        expect(result.node["children"]).to eq([])
        expect(result.errors).not_to be_empty
      end
    end

    it "rejects a path with too many segments" do
      deep = (Array.new(Contract::MAX_PATH_SEGMENTS) { "a" }.join("/")) + "/too_deep.html.erb"
      result = call(fragment("f1", [partial("p1", deep)]))

      expect(result.node["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/path segments/))
    end
  end

  # --- Required args --------------------------------------------------------------

  describe "required args" do
    it "drops a component missing a required arg" do
      result = call(fragment("f1", [component("c1", "modal")]))

      expect(result.node["children"]).to eq([])
      expect(result.errors).to include(a_string_matching(/missing required arg/))
    end

    it "drops an unrecognised extra arg key with a warning, keeping the node" do
      tree = fragment("f1", [component("c1", "modal", "args" => { "id" => "m1", "bogus" => "x" })])
      result = call(tree)

      comp = result.node["children"].first
      expect(comp["args"]).to eq("id" => "m1")
      expect(result.errors).to include(a_string_matching(/dropped unrecognised key/))
    end

    it "drops a builder item missing its required arg" do
      tree = component("nav1", "navbar", "items" => [builder_item("left1", "left", "items" => [builder_item("add1", "add")])])
      result = call(fragment("f1", [tree]))

      expect(result.node["children"].first["items"].first["items"]).to eq([])
      expect(result.errors).to include(a_string_matching(/missing required arg/))
    end
  end
end
