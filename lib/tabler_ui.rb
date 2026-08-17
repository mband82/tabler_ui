# frozen_string_literal: true

require_relative "tabler_ui/version"
require_relative "tabler_ui/engine" if defined?(Rails)
require_relative "tabler_ui/helper"
require_relative "tabler_ui/html_options"
require_relative "tabler_ui/color"
require_relative "tabler_ui/align"
require_relative "tabler_ui/position"
require_relative "tabler_ui/base"
require_relative "tabler_ui/ui"
require_relative "tabler_ui/form_builder"

module TablerUi
  class Error < StandardError; end
end
