# frozen_string_literal: true

require "bundler/gem_tasks"
require_relative "lib/tabler_ui/css_bundle"
require_relative "lib/tabler_ui/usage_doc"

task default: %i[]

namespace :tabler_ui do
  desc "Regenerate app/assets/stylesheets/tabler_ui_all.css from tabler_ui.css's *= require order"
  task :css_bundle do
    path = File.expand_path("app/assets/stylesheets/tabler_ui_all.css", __dir__)
    File.write(path, TablerUi::CssBundle.generate)
    puts "Wrote #{path} (#{File.size(path)} bytes)"
  end

  desc "Regenerate USAGE.md from component doc comments and registered demos"
  task :usage_doc do
    # Can't just require_relative "spec/rails_helper" here: it ends with
    # `require "rspec/rails"` + `RSpec.configure`, and RSpec.configure
    # raises NameError outside an actual rspec run (RSpec itself is never
    # loaded). So this replicates only rails_helper.rb's Combustion-boot
    # lines -- through Combustion.initialize! -- which is all a Rake task
    # needs to get TablerUi::Docs::Navigation/DocParser/DemoRegistry loaded.
    require "combustion"
    require "action_controller/railtie"
    require "action_view/railtie"
    require "tabler_ui"

    Combustion::Application.config.assets = ActiveSupport::OrderedOptions.new
    Combustion::Application.config.assets.paths = []
    Combustion::Application.config.assets.precompile = []

    Combustion.initialize! :action_controller, :action_view

    File.write(TablerUi::UsageDoc::PATH, TablerUi::UsageDoc.generate)
    puts "Wrote #{TablerUi::UsageDoc::PATH} (#{File.size(TablerUi::UsageDoc::PATH)} bytes)"
  end
end
