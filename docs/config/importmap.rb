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
pin "controllers/tabler_ui/docs/editor/dnd", to: "controllers/tabler_ui/docs/editor/dnd.js"
pin "controllers/tabler_ui/docs/editor/drop_target", to: "controllers/tabler_ui/docs/editor/drop_target.js"
pin "controllers/tabler_ui/docs/editor/explorer", to: "controllers/tabler_ui/docs/editor/explorer.js"
pin "controllers/tabler_ui/docs/editor/export", to: "controllers/tabler_ui/docs/editor/export.js"
pin "controllers/tabler_ui/docs/editor/html_escape", to: "controllers/tabler_ui/docs/editor/html_escape.js"
pin "controllers/tabler_ui/docs/editor/inspector", to: "controllers/tabler_ui/docs/editor/inspector.js"
pin "controllers/tabler_ui/docs/editor/overlay", to: "controllers/tabler_ui/docs/editor/overlay.js"
pin "controllers/tabler_ui/docs/editor/palette", to: "controllers/tabler_ui/docs/editor/palette.js"
pin "controllers/tabler_ui/docs/editor/schema", to: "controllers/tabler_ui/docs/editor/schema.js"
pin "controllers/tabler_ui/docs/editor/structure", to: "controllers/tabler_ui/docs/editor/structure.js"
pin "controllers/tabler_ui/docs/editor/tree", to: "controllers/tabler_ui/docs/editor/tree.js"
pin "controllers/tabler_ui/docs/editor/workspace", to: "controllers/tabler_ui/docs/editor/workspace.js"

# Drag-and-drop reordering: a purely additive enhancement on top of the
# move-up/move-down/delete buttons above, which remain the real mechanism
# on a host whose CSP blocks this CDN pin (see editor_sortable_controller.js's
# own header). Namespaced "tabler_ui/docs/sortable", deliberately NOT the
# bare "sortablejs" -- so it can never collide with a host app that pins
# the library itself under its own name, on top of the same-engine overlap
# check spec/lib/tabler_ui/docs/engine_spec.rb already runs.
pin "tabler_ui/docs/sortable", to: "https://cdn.jsdelivr.net/npm/sortablejs@1.15.6/modular/sortable.esm.js"
pin "controllers/tabler_ui/docs/editor_sortable_controller", to: "controllers/tabler_ui/docs/editor_sortable_controller.js"

# Zip export of the whole workspace (editor/export.js). JSZip ships as
# CommonJS only -- no native ESM build -- so a raw jsDelivr file URL would
# not give a real `export default`; esm.sh wraps it into a genuine ES
# module instead. Namespaced "tabler_ui/docs/jszip", deliberately NOT the
# bare "jszip", for the same collision-avoidance reason as the sortable pin
# above, on top of the same-engine overlap check
# spec/lib/tabler_ui/docs/engine_spec.rb already runs.
pin "tabler_ui/docs/jszip", to: "https://esm.sh/jszip@3.10.1"
