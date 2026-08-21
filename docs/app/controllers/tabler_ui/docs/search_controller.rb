# frozen_string_literal: true

require "tabler_ui/docs/search_index"

module TablerUi
  module Docs
    # JSON endpoint backing the docs engine's full-text search: GET
    # /ui/search (see docs/config/routes.rb). Serves
    # TablerUi::Docs::SearchIndex.entries verbatim, as JSON -- filtering
    # happens entirely client-side (see
    # docs/app/javascript/controllers/tabler_ui/docs/search_controller.js),
    # so this action's only job is to hand over the whole index once per
    # page load.
    #
    # Rendered as a real controller action, not a static asset file --
    # sidesteps the Sprockets/Propshaft question entirely for content this
    # dynamic (parsed off component source plus the demo registry), and
    # keeps the index inside Rails' ordinary request cycle rather than
    # needing its own asset-compilation step.
    class SearchController < ApplicationController
      def index
        render json: SearchIndex.entries
      end
    end
  end
end
