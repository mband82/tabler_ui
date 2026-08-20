# frozen_string_literal: true

# Pin npm packages by "downloading" them to vendor/javascript.
# Run bin/importmap outdated to update the version number.

pin "application"

pin "@hotwired/stimulus", to: "https://ga.jspm.io/npm:@hotwired/stimulus@3.2.2/dist/stimulus.js"

# turbo-rails' own engine does not register an importmap pin for itself the
# way tabler_ui's engine does (verified by inspecting Turbo::Engine and
# Rails.application.importmap.packages after `bundle install` -- no
# "@hotwired/turbo-rails" entry appeared). Normally `bin/rails
# turbo:install:importmap` (run once by `rails new` with importmap-rails)
# adds this pin; since this showcase app was never regenerated through that
# installer, it's added by hand here. `turbo.min.js` itself ships in the
# turbo-rails gem's own app/assets/javascripts and is already added to the
# asset precompile list by Turbo::Engine.
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true

pin_all_from Rails.root.join("app/javascript/controllers"), under: "controllers"

# The gem's own config/importmap.rb (tabler_ui, tabler_ui/tabler,
# star-rating.js, apexcharts, the tabler_ui/* Stimulus controllers, and the
# vanillajs-datepicker CDN pin) is appended automatically by
# TablerUi::Engine's `tabler_ui.importmap` initializer, which runs
# `before: "importmap"` and pushes this engine's config/importmap.rb onto
# app.config.importmap.paths.
