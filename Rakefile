# frozen_string_literal: true

require "bundler/gem_tasks"
require_relative "lib/tabler_ui/css_bundle"

task default: %i[]

namespace :tabler_ui do
  desc "Regenerate app/assets/stylesheets/tabler_ui_all.css from tabler_ui.css's *= require order"
  task :css_bundle do
    path = File.expand_path("app/assets/stylesheets/tabler_ui_all.css", __dir__)
    File.write(path, TablerUi::CssBundle.generate)
    puts "Wrote #{path} (#{File.size(path)} bytes)"
  end
end
