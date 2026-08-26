# frozen_string_literal: true

module TablerUi
  module Docs
    # Second mountable engine, isolated from TablerUi::Engine. Serves
    # component documentation. Deliberately does NOT prepend
    # app/components to the view path or inject TablerUi::Helper itself --
    # the main engine's 'tabler_ui.helpers' initializer already installs
    # `helper TablerUi::Helper` on every ActionController::Base descendant
    # process-wide (see lib/tabler_ui/engine.rb), so this engine's own
    # controllers get `tabler_ui` for free. Verified in
    # spec/lib/tabler_ui/docs/engine_spec.rb rather than assumed here.
    #
    # This class MUST be defined at docs/lib/tabler_ui/docs/engine.rb, not
    # lib/tabler_ui/docs/engine.rb. Rails::Engine.find_root walks upward
    # from the directory of the file defining the Engine subclass looking
    # for a directory that itself contains a `lib` subdirectory
    # (find_root_with_flag("lib", called_from), see railties'
    # lib/rails/engine.rb). Defined under the repo's top-level lib/, this
    # class would resolve its root to the repo root -- the same root
    # TablerUi::Engine uses -- and both engines would silently claim the
    # same app/ tree. Defined under docs/lib/, it resolves to docs/,
    # because docs/lib exists. Do not "clean this up" by moving the file or
    # by overriding config.root -- the nested docs/lib is load-bearing.
    class Engine < ::Rails::Engine
      isolate_namespace TablerUi::Docs

      # Named distinctly from the main engine's 'tabler_ui.assets'
      # initializer so the two can never collide. Mirrors that
      # initializer's own three asset paths (see lib/tabler_ui/engine.rb)
      # plus a precompile entry for each -- needed once this engine
      # started shipping its own stylesheet (docs/app/assets/stylesheets/tabler_ui/docs.css,
      # linked by docs/app/views/layouts/tabler_ui/docs/application.html.erb)
      # and JavaScript (docs/app/assets/javascripts/tabler_ui/docs.js,
      # docs/app/javascript/controllers/tabler_ui/docs/*), which the
      # docs/config/importmap.rb pins added for it now need to actually
      # resolve to a real file on Sprockets'/Propshaft's asset paths.
      initializer "tabler_ui.docs.assets" do |app|
        app.config.assets.paths << root.join("app/assets/stylesheets")
        app.config.assets.paths << root.join("app/assets/javascripts")
        app.config.assets.paths << root.join("app/javascript")
        app.config.assets.precompile += %w[
          tabler_ui/docs.css
          tabler_ui/docs.js
          controllers/tabler_ui/docs/search_controller.js
          controllers/tabler_ui/docs/editor_controller.js
          controllers/tabler_ui/docs/editor_sortable_controller.js
          controllers/tabler_ui/docs/editor/explorer.js
          controllers/tabler_ui/docs/editor/export.js
          controllers/tabler_ui/docs/editor/html_escape.js
          controllers/tabler_ui/docs/editor/inspector.js
          controllers/tabler_ui/docs/editor/palette.js
          controllers/tabler_ui/docs/editor/schema.js
          controllers/tabler_ui/docs/editor/structure.js
          controllers/tabler_ui/docs/editor/tree.js
          controllers/tabler_ui/docs/editor/workspace.js
        ]
      end

      # Mirrors the main engine's 'tabler_ui.importmap' initializer. Guarded
      # the same way: importmap-rails is not a dependency of this gem, so
      # in a host (or this gem's own test harness) that hasn't added it,
      # app.config does not respond to :importmap and this is a no-op.
      initializer "tabler_ui.docs.importmap", before: "importmap" do |app|
        app.config.importmap.paths << root.join("config/importmap.rb") if app.config.respond_to?(:importmap)
      end
    end
  end
end
