# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/doc_parser"

# TablerUi::Docs::DocParser turns a component's doc comments into a
# ParsedComponent the (future) docs engine renders as API reference. See
# docs/lib/tabler_ui/docs/doc_parser.rb for the two comment conventions it
# understands.
RSpec.describe TablerUi::Docs::DocParser do
  def fixture_path(name)
    File.join(__dir__, "..", "..", "..", "fixtures", "tabler_ui", "docs", name, "component.rb")
  end

  describe ".parse_file" do
    # This corpus is hand-written specifically for this spec (see the
    # fixtures' own header comments) rather than reused from a real
    # component -- a real component's comments can and will keep changing
    # in wording, and this spec must not go red (or silently stop testing
    # what it claims to) because someone rewrote a paragraph in table.rb.
    context "with a fully documented fixture component" do
      subject(:parsed) { described_class.parse_file(fixture_path("fully_documented")) }

      it "derives the component name from its directory" do
        expect(parsed.name).to eq("fully_documented")
      end

      it "extracts the class-level block's leading prose as description, blank comment lines as paragraph breaks" do
        expect(parsed.description).to eq(
          "Fixture component exercising the doc parser's full feature set.\n\n" \
          "Some leading description prose that spans\nmore than one line, forming a paragraph.\n\n" \
          "A second paragraph, after a blank comment line."
        )
      end

      it "extracts an @example with a title" do
        example = parsed.examples.find { |e| e.title == "With options" }

        expect(example).not_to be_nil
        expect(example.code).to eq('<%= tabler_ui.fixture_full color: "primary" %>')
      end

      it "extracts an @example with no title as a nil title, not an empty string" do
        example = parsed.examples.first

        expect(example.title).to be_nil
        expect(example.code).to eq("<%= tabler_ui.fixture_full %>")
      end

      it "extracts a ## heading as a level-2 section" do
        section = parsed.sections.find { |s| s.title == "Top Section" }

        expect(section.level).to eq(2)
        expect(section.body).to eq("Prose that belongs to the top-level section.")
      end

      it "extracts a ### heading nested under a ## as its own level-3 section, not folded into the parent's body" do
        top = parsed.sections.find { |s| s.title == "Top Section" }
        nested = parsed.sections.find { |s| s.title == "Nested Subsection" }

        expect(nested.level).to eq(3)
        expect(nested.body).to include("distinguishable by its\nlevel rather than by physical nesting")
        # The ### heading line itself, and everything under it, must not
        # have leaked into the preceding ## section's body.
        expect(top.body).not_to include("Nested Subsection")
        expect(top.body).not_to include("distinguishable")
      end

      it "folds multi-line @option continuations into a single description" do
        option = parsed.options.find { |o| o.name == "color" }

        expect(option.type).to eq("String")
        expect(option.description).to eq(
          "Base color, validated against a fixed palette. Continuation line one, testing multi-line " \
          "@option handling across more than one extra line of indented text."
        )
      end

      it "does not choke on a # character inside an @option description" do
        option = parsed.options.find { |o| o.name == "selector" }

        expect(option.type).to eq("String")
        expect(option.description).to eq('CSS selector like "#header", tests a literal # character embedded in text.')
      end

      it "extracts every @option row" do
        expect(parsed.options.map(&:name)).to eq(%w[color selector html])
      end
    end

    context "with a component that has no doc block at all" do
      subject(:parsed) { described_class.parse_file(fixture_path("undocumented")) }

      it "yields a nil description and empty collections instead of raising" do
        expect(parsed.description).to be_nil
        expect(parsed.sections).to eq([])
        expect(parsed.examples).to eq([])
        expect(parsed.options).to eq([])
      end

      it "reports itself as not documented" do
        expect(parsed).not_to be_documented
      end
    end

    context "with a path that does not exist on disk" do
      it "never raises -- returns an empty ParsedComponent instead" do
        expect do
          parsed = described_class.parse_file("/nonexistent/path/component.rb")

          expect(parsed).to be_a(TablerUi::Docs::ParsedComponent)
          expect(parsed.description).to be_nil
          expect(parsed.options).to eq([])
        end.not_to raise_error
      end
    end
  end

  describe ".component_paths" do
    it "walks app/components/tabler_ui/*/component.rb -- the same tree the dispatcher itself uses as its only registry" do
      paths = described_class.component_paths

      expect(paths).not_to be_empty
      expect(paths).to all(match(%r{app/components/tabler_ui/[^/]+/component\.rb\z}))
      expect(paths).to include(a_string_ending_with("app/components/tabler_ui/table/component.rb"))
    end
  end

  # The important one: every real component this gem ships must parse to
  # something a docs page can actually show. If a future component's
  # comment style regresses to a two-line blurb, this goes red instead of
  # the generated docs page silently rendering an empty placeholder for it.
  describe "coverage sweep over every real component" do
    Dir[TablerUi::Engine.root.join("app/components/tabler_ui/*/component.rb")].sort.each do |path|
      name = File.basename(File.dirname(path))

      describe name do
        subject(:parsed) { TablerUi::Docs::DocParser.parse_file(path) }

        it "has a non-empty description" do
          expect(parsed.description).to be_present
        end

        it "has at least one option" do
          expect(parsed.options).not_to be_empty
        end
      end
    end
  end

  describe ".all" do
    around do |example|
      described_class.reset!
      example.run
      described_class.reset!
    end

    it "returns every component keyed by name" do
      all = described_class.all

      expect(all.keys).to match_array(described_class.component_paths.map { |p| File.basename(File.dirname(p)) })
      expect(all["table"]).to be_a(TablerUi::Docs::ParsedComponent)
    end

    it "memoizes: a second call returns the same parsed object when the file hasn't changed on disk" do
      first = described_class.all["spinner"]
      second = described_class.all["spinner"]

      expect(second).to equal(first)
    end

    it "reparses a component whose file mtime changed since it was cached" do
      require "tmpdir"

      Dir.mktmpdir do |dir|
        component_dir = File.join(dir, "app", "components", "tabler_ui", "reload_me")
        FileUtils.mkdir_p(component_dir)
        path = File.join(component_dir, "component.rb")
        File.write(path, "# frozen_string_literal: true\nmodule M\n  class Component\n    def initialize(options = {}); end\n  end\nend\n")

        allow(described_class).to receive(:component_paths).and_return([path])

        first = described_class.all["reload_me"]

        # Bump the mtime forward without changing content -- proves the
        # cache keys on mtime, not a content hash.
        future = Time.now + 5
        File.utime(future, future, path)

        second = described_class.all["reload_me"]

        expect(second).not_to equal(first)
      end
    end
  end

  describe ".find" do
    after { described_class.reset! }

    it "returns the parsed component by name" do
      expect(described_class.find("table")).to be_a(TablerUi::Docs::ParsedComponent)
      expect(described_class.find("table").name).to eq("table")
    end

    it "returns nil for an unknown name" do
      expect(described_class.find("does-not-exist")).to be_nil
    end
  end

  # .builder_options recovers @option rows documented on builder-style
  # components' sub-item methods (NavigationGroup#add, DropDownProxy#item,
  # Tabs#tab, ...) that .find/.all's comment_block_above(lines,
  # INITIALIZE_LINE) never reaches, since that anchor only matches the
  # *first* `def initialize` in the file.
  describe ".builder_options" do
    after { described_class.reset! }

    it "recovers navbar's sub-item @option rows, keyed by enclosing class rather than flattened" do
      result = described_class.builder_options("navbar")
      total = result.values.sum { |methods| methods.values.sum(&:size) }

      # A naive "@option lines above def initialize" minus "@option lines
      # total" count suggests 28 recovered rows, but two of navbar's
      # @option lines never produce an Option in the first place -- one
      # documents two keys on a single `:action, :subject` line (the
      # shared OPTION regex, reused unchanged per the module docs, folds
      # that into one Option named "action,", not two), so the real
      # figure is 27. Asserting a slightly looser floor keeps this from
      # being brittle to that regex's own known quirks.
      expect(total).to be >= 25
      expect(result.keys).to include("NavigationGroup", "DropDownProxy")
    end

    it "keeps NavigationGroup#divider and DropDownProxy#divider as distinct entries with distinct option sets" do
      result = described_class.builder_options("navbar")

      nav_divider = result["NavigationGroup"]["divider"]
      dropdown_divider = result["DropDownProxy"]["divider"]

      expect(nav_divider).not_to be_nil
      expect(dropdown_divider).not_to be_nil
      # Same option name/type (:auth, Object) on both -- only the
      # description text (and which class it's filed under) tells them
      # apart, which is exactly the collision rule 5's own class-keying
      # exists to prevent.
      # DropDownProxy#divider additionally documents :html -- its element is
      # the only one it renders, so that hook was added when the class's
      # missing HTML-attribute parts were filled in. NavigationGroup#divider
      # documents only :auth. The two lists differing is itself part of what
      # class-keying keeps visible.
      expect(nav_divider.map(&:name)).to eq(["auth"])
      expect(dropdown_divider.map(&:name)).to eq(%w[html auth])

      nav_auth = nav_divider.find { |option| option.name == "auth" }
      dropdown_auth = dropdown_divider.find { |option| option.name == "auth" }
      expect(nav_auth.description).not_to eq(dropdown_auth.description)
      expect(nav_auth.description).to include("this group's own :auth")
      expect(dropdown_auth.description).to include("this dropdown's own :auth")
    end

    it "recovers a simpler builder's options under its bare Component class" do
      result = described_class.builder_options("tabs")

      expect(result.keys).to eq(["Component"])
      expect(result["Component"]["tab"].map(&:name)).to include("icon", "badge", "active", "html", "auth")
    end

    it "returns an empty hash for a component with no builder sub-methods" do
      expect(described_class.builder_options("badge")).to eq({})
    end

    it "returns an empty hash for an unknown component name, without raising" do
      expect { described_class.builder_options("does-not-exist") }.not_to raise_error
      expect(described_class.builder_options("does-not-exist")).to eq({})
    end

    it "never leaks into .find's existing output -- navbar's regular option count is unchanged" do
      # Pinned to the value this returned before .builder_options existed
      # (verified by running this spec against main). If this goes red,
      # something about #parse_file's own path changed, not just this
      # new additive one.
      expect(described_class.find("navbar").options.size).to eq(13)
    end
  end
end
