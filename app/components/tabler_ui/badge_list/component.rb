# frozen_string_literal: true

module TablerUi
  module BadgeList
    # BadgeList component for Tabler UI. Renders a `.badges-list` wrapper --
    # a flex container (gap: var(--tblr-list-gap), see tabler.css) meant to
    # hold several `tabler_ui.badge` calls, filled in via a `body` slot.
    #
    # @example
    #   <%= tabler_ui.badge_list do |slots| %>
    #     <% slots.body do %>
    #       <%= tabler_ui.badge text: "New" %>
    #       <%= tabler_ui.badge text: "Hot" %>
    #     <% end %>
    #   <% end %>
    #
    # @example HTML attribute
    #   <%= tabler_ui.badge_list html: { class: "mb-2" } do |slots| %>
    #     <% slots.body do %><%= tabler_ui.badge text: "New" %><% end %>
    #   <% end %>
    class Component
      include TablerUi::Base

      # @param options [Hash]
      # @option options [Hash] :html HTML attributes for the outer `.badges-list` (part :root)
      def initialize(options = {})
        initialize_html_options(options)
      end

      # @return [Hash] attributes for the outer element (part :root)
      def root_attributes
        html_for(:root, class: "badges-list")
      end
    end
  end
end
