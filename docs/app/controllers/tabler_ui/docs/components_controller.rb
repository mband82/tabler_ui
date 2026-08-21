# frozen_string_literal: true

module TablerUi
  module Docs
    # Per-component documentation page: GET /ui/components/:name (see
    # config/routes.rb). Combines the generated API reference
    # (DocParser.find -- description, @option rows, @example blocks, ##
    # prose sections) with the curated live-demo corpus (DemoRegistry.for)
    # for one component. See
    # docs/app/views/tabler_ui/docs/components/show.html.erb for how the two
    # are laid out together, and why @example blocks are never executed.
    class ComponentsController < ApplicationController
      def show
        @name = params[:name].to_s

        return render_not_found unless Navigation.components.include?(@name)

        @nav_current = @name
        @category = Navigation.category_for(@name)

        # DocParser.find never raises and never returns nil for a name that
        # really is on disk (see DocParser's own class docs) -- the fallback
        # here only guards the Navigation-vs-disk drift that
        # navigation_spec.rb already fails the suite over, so this
        # controller degrades to an empty ParsedComponent instead of a 500
        # if that guard ever slips.
        @parsed = DocParser.find(@name) || ParsedComponent.new(@name)
        @demos = DemoRegistry.for(@name.to_sym)
      end

      private

      # A component name that isn't one of Navigation.components (typo'd
      # URL, stale bookmark after a component is removed) -- render a plain
      # 404 rather than raising NoMethodError deep inside the view for a nil
      # @parsed/@demos.
      def render_not_found
        render plain: "Not Found", status: :not_found
      end
    end
  end
end
