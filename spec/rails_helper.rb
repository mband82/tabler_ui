# frozen_string_literal: true

require "spec_helper"

# Combustion boots a minimal Rails application (see spec/internal) so the
# engine can be exercised the way a real host app would use it. "rails"
# has to be loaded before we require the gem itself, since tabler_ui/engine.rb
# only defines TablerUi::Engine (a Rails::Engine subclass) when Rails is
# already defined -- and that definition has to happen before
# Combustion.initialize! runs the engine's initializers.
require "combustion"

# tabler_ui/ui.rb references ActionView::Helpers at load time, so the railtie
# has to be required (which loads the ActionView constant) before we require
# the gem itself.
require "action_controller/railtie"
require "action_view/railtie"
require "tabler_ui"

# The engine's 'tabler_ui.assets' initializer (lib/tabler_ui/engine.rb) pushes
# onto app.config.assets.paths/.precompile, which normally comes from an
# assets railtie (Sprockets/Propshaft). Neither is part of this gem's
# dependencies nor of this test harness, so provide the minimal stand-in the
# initializer needs rather than pulling in an asset pipeline just for specs.
Combustion::Application.config.assets = ActiveSupport::OrderedOptions.new
Combustion::Application.config.assets.paths = []
Combustion::Application.config.assets.precompile = []

# ActiveRecord is intentionally left out: nothing under test touches a
# database, and skipping it keeps the suite fast and the dummy app tiny.
Combustion.initialize! :action_controller, :action_view

require "rspec/rails"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  # Infers type metadata for rspec-rails' own conventional directories
  # (spec/models, spec/requests, ...). It does NOT know about spec/components,
  # since that's a directory we invented for this gem, so it's mapped
  # explicitly below.
  config.infer_spec_type_from_file_location!

  config.define_derived_metadata(file_path: %r{[\\/]spec[\\/]components[\\/]}) do |metadata|
    metadata[:type] ||= :component
  end

  config.include ComponentHelper, type: :component
end
