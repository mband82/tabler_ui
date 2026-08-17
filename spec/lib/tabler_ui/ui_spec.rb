# frozen_string_literal: true

require "rails_helper"

# Exercises TablerUi::Ui#method_missing's three-way dispatch (see
# lib/tabler_ui/ui.rb):
#
#   1. modern  -- class exists and includes TablerUi::Base
#   2. legacy  -- class exists but does NOT include TablerUi::Base
#   3. open struct -- no class at all, bare partial
#
# No real component uses the modern path yet, so those examples define
# throwaway component classes with `stub_const`. They need a partial to
# render against; rather than stubbing the render call, this spec adds
# spec/internal/app/components (the combustion dummy app's own component
# dir -- see spec/rails_helper.rb) as a second view path alongside the
# engine's, and ships matching fixture partials under
# spec/internal/app/components/tabler_ui/spec_*/_component.html.erb. That
# way the dispatcher's real #render_component / #render_block code runs
# unmodified, exactly as it would for a real component.
RSpec.describe TablerUi::Ui do
  # A view context wired up like ComponentHelper's (see
  # spec/support/component_helper.rb), but with the extra spec/internal
  # view path needed for the modern-path fixture partials. Legacy/OpenStruct
  # examples below use real components, which still resolve fine since the
  # engine's app/components path is included too.
  def dispatcher_view_context
    @dispatcher_view_context ||= begin
      view_paths = ActionView::PathSet.new([
        TablerUi::Engine.root.join("app/components").to_s,
        Rails.root.join("app/components").to_s
      ])
      view_class = ActionView::Base.with_empty_template_cache
      view_class.include(TablerUi::Helper)
      view_class.with_view_paths(view_paths, {})
    end
  end

  # Dispatches straight through TablerUi::Ui#method_missing, exactly as
  # `tabler_ui.<name>(...)` would from a real template.
  def dispatch(name, *args, **kwargs, &block)
    dispatcher_view_context.tabler_ui.public_send(name, *args, **kwargs, &block)
  end

  def fragment_for(name, *args, **kwargs, &block)
    Nokogiri::HTML5.fragment(dispatch(name, *args, **kwargs, &block))
  end

  describe "modern path (class includes TablerUi::Base)" do
    it "splits kwargs into required positional args and a trailing options hash" do
      instances = []
      klass = Class.new do
        include TablerUi::Base
        attr_reader :icon, :options

        define_method(:initialize) do |icon, options = {}|
          @icon = icon
          @options = options
          instances << self
        end
      end
      stub_const("TablerUi::SpecWidget::Component", klass)

      dispatch(:spec_widget, icon: "user", size: "lg")

      expect(instances.last.icon).to eq("user")
      expect(instances.last.options).to eq(size: "lg")
    end

    it "passes the whole kwargs hash as options when initialize takes only options" do
      instances = []
      klass = Class.new do
        include TablerUi::Base
        attr_reader :options

        define_method(:initialize) do |options = {}|
          @options = options
          instances << self
        end
      end
      stub_const("TablerUi::SpecOptionsOnly::Component", klass)

      dispatch(:spec_options_only, foo: "bar", baz: 1)

      expect(instances.last.options).to eq(foo: "bar", baz: 1)
    end

    it "raises ArgumentError naming the component and the missing key" do
      klass = Class.new do
        include TablerUi::Base

        def initialize(icon, options = {})
          @icon = icon
          @options = options
        end
      end
      stub_const("TablerUi::SpecWidget::Component", klass)

      expect { dispatch(:spec_widget, size: "lg") }
        .to raise_error(ArgumentError, "tabler_ui.spec_widget requires icon:")
    end

    it "honours explicit positional args from the caller" do
      instances = []
      klass = Class.new do
        include TablerUi::Base
        attr_reader :icon, :options

        define_method(:initialize) do |icon, options = {}|
          @icon = icon
          @options = options
          instances << self
        end
      end
      stub_const("TablerUi::SpecWidget::Component", klass)

      dispatch(:spec_widget, "user", size: "lg")

      expect(instances.last.icon).to eq("user")
      expect(instances.last.options).to eq(size: "lg")
    end

    it "puts extra/unknown keys into the options hash rather than raising" do
      instances = []
      klass = Class.new do
        include TablerUi::Base
        attr_reader :icon, :options

        define_method(:initialize) do |icon, options = {}|
          @icon = icon
          @options = options
          instances << self
        end
      end
      stub_const("TablerUi::SpecWidget::Component", klass)

      expect { dispatch(:spec_widget, icon: "user", unexpected: "value") }.not_to raise_error
      expect(instances.last.icon).to eq("user")
      expect(instances.last.options).to eq(unexpected: "value")
    end
  end

  describe "block dispatch" do
    it "yields the component itself to a component that calls builder_style!" do
      klass = Class.new do
        include TablerUi::Base
        builder_style!

        def initialize(options = {}); end
      end
      stub_const("TablerUi::SpecBuilder::Component", klass)

      yielded = nil
      dispatch(:spec_builder) { |c| yielded = c }

      expect(yielded).to be_a(klass)
    end

    it "yields a SlotContext to a component that doesn't call builder_style!" do
      klass = Class.new do
        include TablerUi::Base

        def initialize(options = {}); end
      end
      stub_const("TablerUi::SpecSlotted::Component", klass)

      yielded = nil
      dispatch(:spec_slotted) { |s| yielded = s }

      expect(yielded).to be_a(TablerUi::SlotContext)
    end

    it "defaults builder_style? to false and does not leak between sibling classes" do
      builder_klass = Class.new { include TablerUi::Base }
      slot_klass = Class.new { include TablerUi::Base }
      builder_klass.builder_style!

      expect(builder_klass.builder_style?).to be(true)
      expect(slot_klass.builder_style?).to be(false)
    end
  end

  # The dispatcher used to carry a third branch for component classes that
  # predated TablerUi::Base, telling keyword-arg constructors from positional
  # view_context ones by inspecting initialize.parameters. Every shipped
  # component now includes TablerUi::Base, so that branch is gone and an
  # unmarked class is an error rather than a guess.
  describe "class that does not include TablerUi::Base" do
    it "raises telling the author to include TablerUi::Base" do
      stub_const("TablerUi::SpecUnmarked::Component", Class.new do
        def initialize(options = {}); end
      end)

      expect { dispatch(:spec_unmarked, text: "x") }
        .to raise_error(ArgumentError, /must `include TablerUi::Base`/)
    end
  end

  describe "real components dispatch through the modern path" do
    it "builds a component with no mandatory arguments from kwargs alone" do
      fragment = fragment_for(:badge, text: "Hello", color: "blue")

      expect(fragment.text).to include("Hello")
      expect(fragment.css(".badge").first["class"]).to include("bg-blue")
    end

    it "yields the component itself to a builder-style component" do
      yielded = nil
      dispatch(:navbar) { |navbar| yielded = navbar }

      expect(yielded).to be_a(TablerUi::Navbar::Component)
      expect(TablerUi::Navbar::Component.builder_style?).to be(true)
    end

    it "yields a SlotContext to a slot-style component" do
      yielded = nil
      dispatch(:alert, color: "info") { |slots| yielded = slots }

      expect(yielded).to be_a(TablerUi::SlotContext)
      expect(TablerUi::Alert::Component.builder_style?).to be(false)
    end
  end

  describe "OpenStruct fallback (no class for this name)" do
    it "wraps kwargs in an OpenStruct and renders the bare partial" do
      # Uses a dedicated fixture partial with no backing class, rather than a
      # real component: real ones get promoted to classes as the refactor
      # proceeds, which would silently move this spec onto a different branch.
      expect("TablerUi::SpecBare::Component".safe_constantize).to be_nil

      expect(OpenStruct).to receive(:new).with({ percent: 42, label: "Loading" }).and_call_original

      fragment = fragment_for(:spec_bare, percent: 42, label: "Loading")

      expect(fragment.css(".spec-bare").attr("data-percent").value).to eq("42")
      expect(fragment.text).to include("Loading")
    end
  end
end
