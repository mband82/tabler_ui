/**
 * Tabler UI Docs Engine JavaScript
 *
 * Entry point for the docs engine's own JavaScript, pinned as
 * "tabler_ui/docs" in docs/config/importmap.rb (loaded automatically by
 * TablerUi::Docs::Engine's 'tabler_ui.docs.importmap' initializer -- see
 * docs/lib/tabler_ui/docs/engine.rb). Mirrors app/assets/javascripts/tabler_ui.js's
 * own "if (window.Stimulus)" registration pattern: Stimulus itself is
 * bootstrapped by whatever mounts this engine, this file only registers
 * the docs engine's own controllers against it once it exists.
 */

import DocsSearchController from "controllers/tabler_ui/docs/search_controller"
import DocsEditorController from "controllers/tabler_ui/docs/editor_controller"
import DocsEditorSortableController from "controllers/tabler_ui/docs/editor_sortable_controller"
import DocsEditorInspectorResizeController from "controllers/tabler_ui/docs/editor_inspector_resize_controller"

if (window.Stimulus) {
  window.Stimulus.register("tabler-ui--docs-search", DocsSearchController)
  // The editor's helper modules under controllers/tabler_ui/docs/editor/ are
  // plain ES modules imported by the controller itself, not Stimulus
  // controllers -- only this one gets registered.
  window.Stimulus.register("tabler-ui--docs-editor", DocsEditorController)
  // Attached to every sortable container the Structure/Explorer panes
  // render (editor/structure.js, editor/explorer.js) -- a purely additive
  // drag-and-drop enhancement on top of those panes' own buttons.
  window.Stimulus.register("tabler-ui--docs-editor-sortable", DocsEditorSortableController)
  // Drives the Inspector rail's drag handle (editor/show.html.erb) --
  // resize-only, knows nothing about the design tree itself.
  window.Stimulus.register("tabler-ui--docs-editor-inspector-resize", DocsEditorInspectorResizeController)
}
