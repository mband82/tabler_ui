# frozen_string_literal: true

require_relative "tabler_ui/version"
require_relative "tabler_ui/engine" if defined?(Rails)
require "tabler_ui/docs" if defined?(Rails)
# Needs TablerUi::Docs::Navigation/DocParser/DemoRegistry (loaded just
# above), so gated the same way -- see usage_doc.rb's own require of
# tabler_ui/docs/navigation and tabler_ui/docs/doc_parser for why those
# two specifically aren't pulled in by the "tabler_ui/docs" require above.
require_relative "tabler_ui/usage_doc" if defined?(Rails)
require_relative "tabler_ui/helper"
require_relative "tabler_ui/html_options"
require_relative "tabler_ui/color"
require_relative "tabler_ui/align"
require_relative "tabler_ui/breakpoint"
require_relative "tabler_ui/position"
require_relative "tabler_ui/frame"
require_relative "tabler_ui/css_bundle"
require_relative "tabler_ui/base"
require_relative "tabler_ui/ui"
require_relative "tabler_ui/form_builder"

module TablerUi
  class Error < StandardError; end
end
