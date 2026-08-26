# frozen_string_literal: true

# Tabler UI Docs engine importmap. Pin names are namespaced under
# "tabler_ui/docs" so they cannot collide with the main engine's pins
# (tabler_ui, tabler_ui/tabler, controllers/tabler_ui/*) -- see
# spec/lib/tabler_ui/docs/engine_spec.rb for the overlap check.
pin "tabler_ui/docs", to: "tabler_ui/docs.js"

# The docs engine's own Stimulus controllers. "controllers/tabler_ui/docs/*"
# rather than "controllers/tabler_ui/*" so it can never collide with the
# main engine's own controller pins (controllers/tabler_ui/alert_controller,
# etc.) -- see spec/lib/tabler_ui/docs/engine_spec.rb's overlap check.
pin "controllers/tabler_ui/docs/search_controller", to: "controllers/tabler_ui/docs/search_controller.js"

# The design editor: one Stimulus controller plus the plain ES modules it
# imports by bare specifier. Every file is pinned individually -- neither
# engine uses pin_all_from, so a new module here means a new pin AND a new
# precompile entry in docs/lib/tabler_ui/docs/engine.rb. Only the controller
# is registered with Stimulus (docs/app/assets/javascripts/tabler_ui/docs.js);
# the rest are imported by it.
pin "controllers/tabler_ui/docs/editor_controller", to: "controllers/tabler_ui/docs/editor_controller.js"
pin "controllers/tabler_ui/docs/editor/explorer", to: "controllers/tabler_ui/docs/editor/explorer.js"
pin "controllers/tabler_ui/docs/editor/html_escape", to: "controllers/tabler_ui/docs/editor/html_escape.js"
pin "controllers/tabler_ui/docs/editor/inspector", to: "controllers/tabler_ui/docs/editor/inspector.js"
pin "controllers/tabler_ui/docs/editor/palette", to: "controllers/tabler_ui/docs/editor/palette.js"
pin "controllers/tabler_ui/docs/editor/schema", to: "controllers/tabler_ui/docs/editor/schema.js"
pin "controllers/tabler_ui/docs/editor/structure", to: "controllers/tabler_ui/docs/editor/structure.js"
pin "controllers/tabler_ui/docs/editor/tree", to: "controllers/tabler_ui/docs/editor/tree.js"
pin "controllers/tabler_ui/docs/editor/workspace", to: "controllers/tabler_ui/docs/editor/workspace.js"
