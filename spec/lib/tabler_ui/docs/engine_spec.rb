# frozen_string_literal: true

require "rails_helper"

# TablerUi::Docs::Engine is a second, independently-rooted mountable engine
# (see docs/lib/tabler_ui/docs/engine.rb for why it must live under docs/lib
# rather than the top-level lib/). This spec proves, against a real booted
# Rails app (Combustion, see spec/rails_helper.rb), that:
#
#   1. the two engines resolve to two different roots
#   2. the docs engine is actually mounted and serves a page
#      (spec/internal/config/routes.rb mounts it at "/ui")
#   3. TablerUi::Helper -- and therefore the `tabler_ui.*` component
#      dispatcher -- is available inside the docs engine's own controllers
#      and views without this engine wiring it in itself
#   4. the two engines' importmap pins never collide
RSpec.describe "TablerUi::Docs::Engine", type: :request do
  describe "engine roots" do
    it "resolves to the docs/ directory, distinct from TablerUi::Engine's root" do
      expect(TablerUi::Docs::Engine.root.to_s).to end_with("/docs")
      expect(TablerUi::Docs::Engine.root.to_s).not_to eq(TablerUi::Engine.root.to_s)
    end
  end

  describe "mounted engine" do
    it "renders 200 at its mount point" do
      get "/ui"

      expect(response).to have_http_status(:ok)
    end

    it "renders a real tabler_ui component (proves the pipeline works inside the engine)" do
      get "/ui"

      # app/components/tabler_ui/icon/component.rb emits raw SVG carrying
      # this class on every icon, filled or outline.
      expect(response.body).to include("icon-tabler-home")
    end
  end

  describe "TablerUi::Helper availability" do
    it "is already present on the docs engine's ApplicationController, without this engine injecting it" do
      # lib/tabler_ui/engine.rb's 'tabler_ui.helpers' initializer installs
      # `helper TablerUi::Helper` on every ActionController::Base descendant
      # process-wide via ActiveSupport.on_load(:action_controller_base).
      # docs/lib/tabler_ui/docs/engine.rb deliberately does not repeat that
      # -- this asserts the claim rather than assuming it.
      expect(TablerUi::Docs::ApplicationController._helpers.ancestors).to include(TablerUi::Helper)
    end
  end

  describe "importmap pin names" do
    def pin_names(path)
      File.read(path).scan(/^\s*pin\s+["']([^"']+)["']/).flatten
    end

    it "never overlaps between the main engine and the docs engine" do
      main_pins = pin_names(TablerUi::Engine.root.join("config/importmap.rb"))
      docs_pins = pin_names(TablerUi::Docs::Engine.root.join("config/importmap.rb"))

      expect(main_pins).not_to be_empty
      expect(docs_pins).not_to be_empty
      expect(main_pins & docs_pins).to eq([])
    end
  end

  describe "importmap precompile coverage" do
    # Same textual scan as pin_names above, but capturing the `to:` target
    # rather than the pin name, and dropping CDN pins -- a pin to an
    # absolute http(s) URL (the main engine's vanillajs-datepicker) is
    # fetched by the browser directly and has no local file to precompile.
    def local_pin_targets(path)
      File.read(path)
          .scan(/^\s*pin\s+["'][^"']+["'],\s*to:\s*["']([^"']+)["']/)
          .flatten
          .reject { |target| target.start_with?("http://", "https://") }
    end

    # Guards the same failure mode fixed in docs/lib/tabler_ui/docs/engine.rb
    # (a docs.css precompile omission): an asset the docs engine references
    # but never adds to app.config.assets.precompile works in development
    # (Sprockets compiles on demand) but 404s under check_precompiled_asset
    # in production. This half covers importmap-pinned JS; the
    # stylesheet_link_tag half below is what actually covers docs.css.
    it "precompiles every locally-pinned docs asset" do
      docs_targets = local_pin_targets(TablerUi::Docs::Engine.root.join("config/importmap.rb"))

      expect(docs_targets).not_to be_empty
      expect(docs_targets - Rails.application.config.assets.precompile).to eq([])
    end

    # The other half, and the one that would actually have caught the
    # docs.css omission: a stylesheet the layout links is never an importmap
    # pin, so the check above structurally cannot see it. Scans the layout
    # for the logical names it links and asserts each is precompiled --
    # ".css" appended because stylesheet_link_tag takes the extensionless
    # name while the precompile list carries the real filename.
    def linked_stylesheets(path)
      File.read(path).scan(/stylesheet_link_tag\s+["']([^"']+)["']/).flatten
    end

    it "precompiles every stylesheet the docs layout links" do
      layout = TablerUi::Docs::Engine.root.join("app/views/layouts/tabler_ui/docs/application.html.erb")
      linked = linked_stylesheets(layout).map { |name| "#{name}.css" }

      expect(linked).not_to be_empty

      # tabler_ui_all.css belongs to the main engine, which precompiles it
      # in its own 'tabler_ui.assets' initializer -- both engines' entries
      # land in the same app-level list, so checking against that list
      # covers the layout's full set regardless of which engine owns each.
      expect(linked - Rails.application.config.assets.precompile).to eq([])
    end
  end
end
