# frozen_string_literal: true

# TablerUi::Docs::Navigation, ::DocParser and ::ParsedComponent live under
# docs/lib/tabler_ui/docs/*.rb, which is on $LOAD_PATH (see the gemspec's
# require_paths) but NOT Zeitwerk-autoloaded and NOT required by
# docs/lib/tabler_ui/docs.rb at gem-boot time (that file only requires
# engine/demo/demo_registry -- see its own comment). Required here, once, so
# every controller under this engine -- and the layout's sidebar partial,
# rendered on every one of their pages -- can reference these constants
# without each page controller repeating the require.
require "tabler_ui/docs/navigation"
require "tabler_ui/docs/doc_parser"

module TablerUi
  module Docs
    class ApplicationController < ActionController::Base
      layout "tabler_ui/docs/application"
    end
  end
end
