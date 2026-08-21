# frozen_string_literal: true

module TablerUi
  module Docs
    class PagesController < ApplicationController
      def home; end

      # Cross-cutting reference for the html: / <part>_html: mechanism --
      # see docs/app/views/tabler_ui/docs/pages/html_attributes.html.erb.
      # Not a component (no app/components/tabler_ui directory), so it gets
      # its own top-level sidebar entry, same pattern as FormsController
      # marking Navigation::FORM_BUILDER active -- see Navigation::HTML_ATTRIBUTES.
      def html_attributes
        @nav_current = Navigation::HTML_ATTRIBUTES
      end
    end
  end
end
