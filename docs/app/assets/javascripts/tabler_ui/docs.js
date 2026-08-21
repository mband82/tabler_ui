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

if (window.Stimulus) {
  window.Stimulus.register("tabler-ui--docs-search", DocsSearchController)
}
