// Showcase entry point (pinned as "application" in config/importmap.rb).
//
// Turbo Drive/Frames first -- turns on Turbo navigation for the whole
// showcase (the realistic host-app condition) and is what makes the
// table/pagination `frame:` demo actually work.
//
// Order matters below that: controllers/application must run before
// tabler_ui so that window.Stimulus exists before tabler_ui.js's top-level
// `if (window.Stimulus) { ... register ... }` guard runs.
import "@hotwired/turbo-rails"
import "controllers/application"
import "tabler_ui"
