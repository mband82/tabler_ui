# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor"
require "tabler_ui/docs/editor/workspace"

# Workspace validates the multi-file document one level above Tree (which
# validates a single design) -- see workspace.rb's own header for the full
# rationale, especially the "Cycle handling" section this suite exercises
# most heavily.
#
# TablerUi.auth_method (lib/tabler_ui.rb) is the order-dependent global state
# other spec files mutate -- see tree_spec.rb's own note on it. Nothing here
# reads or writes it either: Tree.call (which every valid-file example below
# runs through) only ever *reports* the string "auth", it never calls
# TablerUi::Authorization, so no `around` block is needed. Every example
# below is still written to stand on its own regardless of --seed / run
# order.
RSpec.describe TablerUi::Docs::Editor::Workspace do
  Contract = TablerUi::Docs::Editor::Contract

  def call(raw)
    described_class.call(raw)
  end

  # --- Tree-shaped node builders (mirrors tree_spec.rb's own helpers) -------

  def node(kind, id, extra = {})
    { "kind" => kind, "id" => id }.merge(extra)
  end

  def fragment(id, children = [])
    node("fragment", id, "children" => children)
  end

  def text(id, content = "Hello")
    node("text", id, "tag" => "p", "content" => content)
  end

  def partial(id, path)
    node("partial", id, "path" => path)
  end

  # A minimal, always-valid single-node tree -- used wherever a test only
  # cares about workspace-level behaviour, not what Tree does with the tree.
  def min_tree(id = "root")
    fragment(id)
  end

  def file(tree)
    { "tree" => tree }
  end

  def workspace(files: {}, directories: [], open: nil, version: Contract::VERSION)
    { "version" => version, "files" => files, "directories" => directories, "open" => open }
  end

  # --- Valid multi-file workspace ---------------------------------------------

  describe "a valid multi-file workspace" do
    it "normalizes files, directories and open" do
      raw = workspace(
        files: {
          "index.html.erb" => file(fragment("f1", [text("t1")])),
          "shared/_header.html.erb" => file(min_tree("f2"))
        },
        directories: %w[shared empty_dir],
        open: "index.html.erb"
      )
      result = call(raw)

      expect(result.fatal?).to be false
      expect(result.errors).to eq([])
      expect(result.workspace["version"]).to eq(Contract::VERSION)
      expect(result.workspace["files"].keys).to contain_exactly("index.html.erb", "shared/_header.html.erb")
      expect(result.workspace["open"]).to eq("index.html.erb")
      # "shared" is implied by "shared/_header.html.erb" and is dropped;
      # "empty_dir" has no file in it, so it survives.
      expect(result.workspace["directories"]).to eq(["empty_dir"])
    end
  end

  # --- Bad path forms (rule 2) -------------------------------------------------

  describe "invalid file paths" do
    bad_paths = {
      "parent traversal" => "../etc/passwd.html.erb",
      "leading slash" => "/abs/path.html.erb",
      "missing suffix" => "no-suffix",
      "double slash (empty segment)" => "a//b.html.erb",
      "backslash" => "a\\b.html.erb"
    }

    bad_paths.each do |label, bad_path|
      it "drops a file at an invalid path (#{label}) without failing the workspace" do
        raw = workspace(files: { bad_path => file(min_tree) }, open: bad_path)
        result = call(raw)

        expect(result.fatal?).to be false
        expect(result.workspace["files"]).to eq({})
        expect(result.errors).to include(a_string_matching(/invalid path, file dropped/))
      end
    end

    it "drops a file whose path has more than MAX_PATH_SEGMENTS segments" do
      deep = (Array.new(Contract::MAX_PATH_SEGMENTS) { "a" }.join("/")) + "/too_deep.html.erb"
      result = call(workspace(files: { deep => file(min_tree) }))

      expect(result.workspace["files"]).to eq({})
      expect(result.errors).to include(a_string_matching(/invalid path, file dropped/))
    end
  end

  # --- File cap (rule 4) --------------------------------------------------------

  describe "the file cap" do
    it "keeps the first LIMITS[:files] entries and drops the rest with one error" do
      over = Contract::LIMITS[:files] + 5
      files = {}
      over.times { |i| files["file#{i}.html.erb"] = file(min_tree) }

      result = call(workspace(files: files))

      expect(result.workspace["files"].size).to eq(Contract::LIMITS[:files])
      expect(result.errors).to include(a_string_matching(/exceeds the #{Contract::LIMITS[:files]} limit/))
    end
  end

  # --- Fatal tree drops the file, siblings survive (rule 3) --------------------

  describe "a file with a fatal tree" do
    it "is dropped with an error while sibling files survive" do
      raw = workspace(
        files: {
          "bad.html.erb" => file({ "kind" => "not_a_real_kind", "id" => "x" }),
          "good.html.erb" => file(min_tree)
        }
      )
      result = call(raw)

      expect(result.fatal?).to be false
      expect(result.workspace["files"].keys).to eq(["good.html.erb"])
      expect(result.errors).to include(a_string_matching(/bad\.html\.erb: .*tree is fatal, file dropped/))
    end

    it "prefixes a non-fatal tree error with the file path so it's traceable" do
      # A duplicate id inside one tree is a Tree-level error, not fatal.
      raw = workspace(
        files: {
          "dup.html.erb" => file(fragment("f1", [text("t1"), node("text", "t1", "tag" => "p", "content" => "x")]))
        }
      )
      result = call(raw)

      expect(result.workspace["files"]).to have_key("dup.html.erb")
      expect(result.errors).to include(a_string_matching(/\Adup\.html\.erb: .*duplicate id/))
    end
  end

  # --- `open` fallback (rule 6) -------------------------------------------------

  describe "open" do
    it "falls back to the first file (sorted) when open names a file that didn't survive" do
      raw = workspace(
        files: { "z.html.erb" => file(min_tree), "a.html.erb" => file(min_tree) },
        open: "missing.html.erb"
      )
      result = call(raw)

      expect(result.workspace["open"]).to eq("a.html.erb")
      expect(result.errors).to include(a_string_matching(/open: .*falling back to "a\.html\.erb"/))
    end

    it "falls back to nil when there are no surviving files at all" do
      result = call(workspace(files: {}, open: "nope.html.erb"))

      expect(result.workspace["open"]).to be_nil
      expect(result.errors).to include(a_string_matching(/falling back to nil/))
    end
  end

  # --- Cycles (rule 7) ----------------------------------------------------------

  describe "partial reference cycles" do
    it "detects and reports a direct self-reference" do
      raw = workspace(
        files: { "a.html.erb" => file(fragment("f1", [partial("p1", "a.html.erb")])) }
      )
      result = call(raw)

      expect(result.fatal?).to be false
      expect(result.errors).to include("cycle detected: a.html.erb -> a.html.erb")
      # The file itself is still a real, editable file...
      expect(result.workspace["files"]).to have_key("a.html.erb")
      # ...but it can never resolve as a partial-render target.
      expect(result.resolve.call("a.html.erb")).to be_nil
    end

    it "detects and reports a 2-file loop" do
      raw = workspace(
        files: {
          "a.html.erb" => file(fragment("fa", [partial("pa", "b.html.erb")])),
          "b.html.erb" => file(fragment("fb", [partial("pb", "a.html.erb")]))
        }
      )
      result = call(raw)

      expect(result.errors).to include("cycle detected: a.html.erb -> b.html.erb -> a.html.erb")
      expect(result.workspace["files"].keys).to contain_exactly("a.html.erb", "b.html.erb")
      expect(result.resolve.call("a.html.erb")).to be_nil
      expect(result.resolve.call("b.html.erb")).to be_nil
    end

    it "detects and reports a 3-file loop" do
      raw = workspace(
        files: {
          "a.html.erb" => file(fragment("fa", [partial("pa", "b.html.erb")])),
          "b.html.erb" => file(fragment("fb", [partial("pb", "c.html.erb")])),
          "c.html.erb" => file(fragment("fc", [partial("pc", "a.html.erb")]))
        }
      )
      result = call(raw)

      expect(result.errors).to include("cycle detected: a.html.erb -> b.html.erb -> c.html.erb -> a.html.erb")
      %w[a.html.erb b.html.erb c.html.erb].each do |path|
        expect(result.resolve.call(path)).to be_nil
      end
    end

    it "does not flag a diamond (b and c both reaching d) as a cycle" do
      raw = workspace(
        files: {
          "a.html.erb" => file(fragment("fa", [partial("pb", "b.html.erb"), partial("pc", "c.html.erb")])),
          "b.html.erb" => file(fragment("fb", [partial("pd1", "d.html.erb")])),
          "c.html.erb" => file(fragment("fc", [partial("pd2", "d.html.erb")])),
          "d.html.erb" => file(min_tree("fd"))
        },
        open: "a.html.erb"
      )
      result = call(raw)

      expect(result.errors).to eq([])
      %w[a.html.erb b.html.erb c.html.erb d.html.erb].each do |path|
        expect(result.resolve.call(path)).not_to be_nil
      end
    end
  end

  # --- Broken partial reference (rule 7, second half) ---------------------------

  describe "a broken partial reference" do
    it "is recorded as an error but is not fatal and does not drop the referencing file" do
      raw = workspace(
        files: { "a.html.erb" => file(fragment("fa", [partial("pm", "missing.html.erb")])) }
      )
      result = call(raw)

      expect(result.fatal?).to be false
      expect(result.workspace["files"]).to have_key("a.html.erb")
      expect(result.errors).to include(a_string_matching(/a\.html\.erb: partial reference to "missing\.html\.erb" does not resolve/))
      # "a" itself isn't cyclic, so it still resolves fine as a target.
      expect(result.resolve.call("a.html.erb")).not_to be_nil
    end
  end

  # --- version (rule 1) ----------------------------------------------------------

  describe "version" do
    it "is fatal when newer than Contract::VERSION" do
      result = call(workspace(version: Contract::VERSION + 1))

      expect(result.fatal?).to be true
      expect(result.workspace).to be_nil
      expect(result.errors).to include(a_string_matching(/newer than this editor supports/))
    end

    it "is fatal when older than Contract::VERSION" do
      result = call(workspace(version: Contract::VERSION - 1))

      expect(result.fatal?).to be true
      expect(result.errors).to include(a_string_matching(/older than current/))
    end

    it "is fatal when not an Integer" do
      result = call(workspace(version: "1"))

      expect(result.fatal?).to be true
      expect(result.errors).to include(a_string_matching(/must be an Integer/))
    end
  end

  # --- Never raises on garbage (rule: hostile payload) ---------------------------

  describe "garbage input" do
    [nil, "a string", [], 42, true].each do |garbage|
      it "returns a fatal Result without raising for #{garbage.inspect}" do
        result = nil
        expect { result = call(garbage) }.not_to raise_error

        expect(result.fatal?).to be true
        expect(result.errors).not_to be_empty
        expect(result.resolve).to be_nil
      end
    end

    it "never raises when files/directories/open are the wrong shape entirely" do
      raw = { "version" => Contract::VERSION, "files" => "nope", "directories" => 123, "open" => %w[not a string] }
      result = nil
      expect { result = call(raw) }.not_to raise_error

      expect(result.fatal?).to be false
      expect(result.workspace["files"]).to eq({})
      expect(result.workspace["directories"]).to eq([])
      expect(result.workspace["open"]).to be_nil
    end

    it "never raises when a file entry is deeply nested junk instead of a Hash" do
      raw = workspace(files: { "a.html.erb" => { "tree" => { "kind" => "fragment", "id" => "f1",
                                                               "children" => [[1, [2, [3, {}]]]] } } })
      result = nil
      expect { result = call(raw) }.not_to raise_error
      expect(result.fatal?).to be false
    end

    it "never raises when a file's value isn't a Hash at all" do
      raw = workspace(files: { "a.html.erb" => "not a hash", "b.html.erb" => 42, "c.html.erb" => [1, 2, 3] })
      result = nil
      expect { result = call(raw) }.not_to raise_error

      expect(result.workspace["files"]).to eq({})
      expect(result.errors.count { |e| e.include?("expected an object with a 'tree' key") }).to eq(3)
    end
  end
end
