// Showcase entry point (pinned as "application" in config/importmap.rb).
//
// Order matters: controllers/application must run first so that
// window.Stimulus exists before tabler_ui.js's top-level
// `if (window.Stimulus) { ... register ... }` guard runs.
import "controllers/application"
import "tabler_ui"
