# frozen_string_literal: true

# Pin npm packages by "downloading" them to vendor/javascript.
# Run bin/importmap outdated to update the version number.

pin "application"

pin "@hotwired/stimulus", to: "https://ga.jspm.io/npm:@hotwired/stimulus@3.2.2/dist/stimulus.js"

pin_all_from Rails.root.join("app/javascript/controllers"), under: "controllers"

# The gem's own config/importmap.rb (tabler_ui, tabler_ui/tabler,
# star-rating.js, apexcharts, the tabler_ui/* Stimulus controllers, and the
# vanillajs-datepicker CDN pin) is appended automatically by
# TablerUi::Engine's `tabler_ui.importmap` initializer, which runs
# `before: "importmap"` and pushes this engine's config/importmap.rb onto
# app.config.importmap.paths.
