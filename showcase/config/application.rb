# frozen_string_literal: true

require_relative "boot"

require "rails"
# Only the railties this showcase actually needs -- no ActiveRecord, no
# database, every component here is a stateless view helper. The forms page
# uses a plain ActiveModel::Model double, hence active_model/railtie.
require "active_model/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "sprockets/railtie"

Bundler.require(*Rails.groups)

module Showcase
  class Application < Rails::Application
    config.load_defaults 8.1

    # No database in this showcase.
    config.generators.system_tests = nil

    config.action_controller.perform_caching = false

    # Sprockets, not Propshaft: tabler_ui.css is a Sprockets directive
    # manifest (`*= require ...`) shipped by the gem.
    config.assets.css_compressor = nil
    config.assets.js_compressor = nil
  end
end
