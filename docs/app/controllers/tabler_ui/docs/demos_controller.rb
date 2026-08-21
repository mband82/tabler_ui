# frozen_string_literal: true

module TablerUi
  module Docs
    # Proves the demo mechanism is reachable through the mounted engine:
    # GET /ui/demos/:component renders every registered Demo for one
    # component via docs/app/views/tabler_ui/docs/demos/_demo.html.erb.
    # A real per-component page (nav, breadcrumbs, parsed @example blocks
    # alongside these runnable demos) is other agents' work -- this action
    # exists only to exercise the render path end to end.
    class DemosController < ApplicationController
      def show
        @component = params[:component].to_sym
        @demos = DemoRegistry.for(@component)
      end
    end
  end
end
