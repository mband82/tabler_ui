# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true

  config.action_controller.perform_caching = false
  config.action_controller.raise_on_missing_callback_actions = true

  config.public_file_server.enabled = true

  config.assets.debug = true
  config.assets.quiet = true

  config.log_level = :debug

  # Dev-only showcase, not exposed beyond localhost -- skip host authorization.
  config.hosts.clear
end
