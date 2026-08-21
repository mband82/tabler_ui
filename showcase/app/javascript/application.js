// Showcase entry point (pinned as "application" in config/importmap.rb).
//
// Turbo Drive/Frames first -- turns on Turbo navigation for the whole
// showcase (the realistic host-app condition) and is what makes the
// table/pagination `frame:` demo actually work.
//
// Order matters below that: controllers/application must run before
// tabler_ui (and tabler_ui/docs) so that window.Stimulus exists before
// either one's top-level `if (window.Stimulus) { ... register ... }`
// guard runs -- see app/assets/javascripts/tabler_ui.js and
// docs/app/assets/javascripts/tabler_ui/docs.js.
//
// This showcase app is now TablerUi::Docs::Engine's mount point (see
// config/routes.rb) -- "tabler_ui/docs" registers the docs engine's own
// Stimulus controllers (currently just tabler-ui--docs-search) the same
// way "tabler_ui" registers the main gem's.
import "@hotwired/turbo-rails"
import "controllers/application"
import "tabler_ui"
import "tabler_ui/docs"
