# frozen_string_literal: true

require "rails_helper"

# Exercises the demo mechanism documented in docs/DEMOS.md: one ERB string
# (Demo#source) that is both rendered live and printed as its own code
# sample. TablerUi::Docs::DemoRegistry.load_demos! already ran once at gem
# boot (docs/lib/tabler_ui/docs.rb), via `require "tabler_ui/docs" if
# defined?(Rails)` in lib/tabler_ui.rb, so DemoRegistry.all already holds
# every demo from docs/lib/tabler_ui/docs/demos/*_demos.rb -- including any
# other agent adds -- by the time this spec runs.
RSpec.describe "TablerUi::Docs::DemoRegistry" do
  # Builds a real view context wired up with BOTH the main engine's component
  # view path (so `tabler_ui.badge`/`tabler_ui.card` resolve) and the docs
  # engine's view path (so the "tabler_ui/docs/demos/demo" partial resolves).
  # Mirrors spec/support/component_helper.rb's #tabler_ui_view_context; not
  # reused directly since that helper only wires up the main engine's path
  # and lives outside this task's docs/ + spec/lib/tabler_ui/docs/ boundary.
  def demo_view_context
    view_paths = ActionView::PathSet.new([
                                            TablerUi::Engine.root.join("app/components").to_s,
                                            TablerUi::Docs::Engine.root.join("app/views").to_s
                                          ])
    view_class = ActionView::Base.with_empty_template_cache
    view_class.include(TablerUi::Helper)
    view_class.with_view_paths(view_paths, {})
  end

  describe "the DSL" do
    after do
      # Builder#demo mutates the same process-wide registry every other spec
      # (and, at boot, every real demos file) reads from. Any component
      # symbol invented for a single example here must not survive it.
      %i[demo_registry_spec_fixture demo_registry_spec_fixture_a demo_registry_spec_fixture_b].each do |component|
        TablerUi::Docs::DemoRegistry.send(:registry).delete(component)
      end
    end

    it "registers demos via DemoRegistry.define/c.demo, in order, readable via .for" do
      TablerUi::Docs::DemoRegistry.define(:demo_registry_spec_fixture) do |c|
        c.demo :first, title: "first demo", source: "<%= 1 + 1 %>"
        c.demo :second, title: "second demo", source: "<%= 2 + 2 %>"
      end

      demos = TablerUi::Docs::DemoRegistry.for(:demo_registry_spec_fixture)

      expect(demos.map(&:id)).to eq(%i[first second])
      expect(demos.map(&:title)).to eq(["first demo", "second demo"])
      expect(demos.map(&:component)).to eq(%i[demo_registry_spec_fixture demo_registry_spec_fixture])
    end

    it "raises when an id is reused within one component" do
      expect do
        TablerUi::Docs::DemoRegistry.define(:demo_registry_spec_fixture) do |c|
          c.demo :dup, title: "a", source: "a"
          c.demo :dup, title: "b", source: "b"
        end
      end.to raise_error(TablerUi::Docs::DemoRegistry::DuplicateDemoError, /:dup/)
    end

    it "allows the same id across two different components" do
      expect do
        TablerUi::Docs::DemoRegistry.define(:demo_registry_spec_fixture_a) { |c| c.demo :same, title: "a", source: "a" }
        TablerUi::Docs::DemoRegistry.define(:demo_registry_spec_fixture_b) { |c| c.demo :same, title: "b", source: "b" }
      end.not_to raise_error
    end

    it "raises when two different (component, id) pairs concatenate to the same slug" do
      # component :"demo-registry-fixture-foo-bar", id :baz -> "demo-registry-fixture-foo-bar-baz"
      # component :"demo-registry-fixture-foo", id :"bar-baz" -> same string, different pair.
      # DemoRegistry must catch this even though neither component reuses the other's id.
      first = TablerUi::Docs::Demo.new(:baz, :"demo-registry-fixture-foo-bar", title: "x", source: "x")
      second = TablerUi::Docs::Demo.new(:"bar-baz", :"demo-registry-fixture-foo", title: "y", source: "y")
      expect(first.slug).to eq(second.slug)

      TablerUi::Docs::DemoRegistry.register(first)
      begin
        expect { TablerUi::Docs::DemoRegistry.register(second) }
          .to raise_error(TablerUi::Docs::DemoRegistry::DuplicateDemoError, /slug/)
      ensure
        TablerUi::Docs::DemoRegistry.send(:registry).delete(:"demo-registry-fixture-foo-bar")
        TablerUi::Docs::DemoRegistry.send(:registry).delete(:"demo-registry-fixture-foo")
      end
    end

    it "computes a globally-unique slug as '<component>-<id>'" do
      demo = TablerUi::Docs::Demo.new(:colors, :badge, title: "x", source: "x")

      expect(demo.slug).to eq("badge-colors")
    end
  end

  describe "loading demo files" do
    it "is idempotent -- calling load_demos! again does not duplicate any component's demos" do
      before_counts = TablerUi::Docs::DemoRegistry.components.index_with { |c| TablerUi::Docs::DemoRegistry.for(c).size }

      TablerUi::Docs::DemoRegistry.load_demos!
      TablerUi::Docs::DemoRegistry.load_demos!

      after_counts = TablerUi::Docs::DemoRegistry.components.index_with { |c| TablerUi::Docs::DemoRegistry.for(c).size }
      expect(after_counts).to eq(before_counts)
    end

    it "has already registered the five reference components at boot" do
      expect(TablerUi::Docs::DemoRegistry.components).to include(:badge, :alert, :avatar, :spinner, :progress)
    end
  end

  describe "DemoRegistry.find" do
    it "finds a demo by its slug" do
      demo = TablerUi::Docs::DemoRegistry.find("badge-colors")

      expect(demo).to be_a(TablerUi::Docs::Demo)
      expect(demo.component).to eq(:badge)
      expect(demo.id).to eq(:colors)
    end

    it "returns nil for an unknown slug" do
      expect(TablerUi::Docs::DemoRegistry.find("nope-nope")).to be_nil
    end
  end

  # The regression net this whole mechanism exists for: showcase_helper.rb's
  # separately-maintained SNIPPETS hash could (and did) drift from the live
  # ERB it claimed to describe, because nothing ever rendered the snippet
  # itself. Every demo's source is the thing that gets rendered AND printed,
  # so if it doesn't actually render, this catches it immediately -- and it
  # automatically covers every demo any other agent registers, not just
  # this file's own five components.
  describe "every registered demo" do
    it "renders its source via render inline: without raising" do
      TablerUi::Docs::DemoRegistry.all.each do |demo|
        view = demo_view_context

        expect do
          view.render(inline: demo.source, locals: demo.resolved_locals)
        end.not_to raise_error, "#{demo.slug} failed to render"
      end
    end

    it "has a non-empty source and title" do
      TablerUi::Docs::DemoRegistry.all.each do |demo|
        expect(demo.source).to be_present
        expect(demo.title).to be_present
      end
    end
  end

  describe "the five reference components" do
    it "badge has 3 demos" do
      expect(TablerUi::Docs::DemoRegistry.for(:badge).map(&:id)).to eq(%i[colors dot icon_only])
    end

    it "alert has 4 demos" do
      expect(TablerUi::Docs::DemoRegistry.for(:alert).map(&:id)).to eq(%i[colors minor muted link_style])
    end

    it "avatar has 3 demos" do
      expect(TablerUi::Docs::DemoRegistry.for(:avatar).map(&:id)).to eq(%i[basics cover overlay])
    end

    it "spinner has 1 demo" do
      expect(TablerUi::Docs::DemoRegistry.for(:spinner).map(&:id)).to eq(%i[variants])
    end

    it "progress has 3 demos" do
      expect(TablerUi::Docs::DemoRegistry.for(:progress).map(&:id)).to eq(%i[variants indeterminate separated])
    end
  end

  describe "the _demo partial" do
    it "renders both the live output and the escaped source, and the source matches the demo's source" do
      demo = TablerUi::Docs::DemoRegistry.find("badge-colors")
      view = demo_view_context

      html = view.render("tabler_ui/docs/demos/demo", demo: demo)

      # Live output: the badge component actually rendered, not just its source text.
      expect(html).to include('class="badge')
      expect(html).to match(/>\s*New\s*</)

      # Source: printed escaped (raw "<%=" must not appear unescaped in the
      # HTML -- it must show up as the escaped entity), inside <pre><code>,
      # and textually equal to the demo's own source once un-escaped.
      expect(html).not_to include("<%= tabler_ui.badge")
      expect(html).to include("&lt;%= tabler_ui.badge")

      fragment = Nokogiri::HTML5.fragment(html)
      printed_source = fragment.at_css("pre code").text
      expect(printed_source).to eq(demo.source.strip)
    end
  end
end
