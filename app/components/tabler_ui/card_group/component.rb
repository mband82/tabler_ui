# frozen_string_literal: true

module TablerUi
  module CardGroup
    # CardGroup component for Tabler UI. Renders a `.card-group` wrapper
    # meant to hold several `tabler_ui.card` calls, filled in via a `body`
    # slot.
    #
    # Verified CSS contract (see .card-group rules in tabler.css): the cards
    # must be *direct children* of `.card-group` -- `.card-group > .card`
    # uses a direct-child combinator, and the corner-rounding rules key off
    # `:not(:first-child)` / `:not(:last-child)` on that same direct-child
    # relationship. Do not wrap the cards in an intermediate `<div>` inside
    # the body slot, or the flex layout and rounded-corner rules silently
    # stop applying. DOM order matters too -- first/last child determine
    # which corners stay rounded.
    #
    # @example
    #   <%= tabler_ui.card_group do |slots| %>
    #     <% slots.body do %>
    #       <%= tabler_ui.card title: "One" do |card_slots| %>
    #         <% card_slots.body { "First" } %>
    #       <% end %>
    #       <%= tabler_ui.card title: "Two" do |card_slots| %>
    #         <% card_slots.body { "Second" } %>
    #       <% end %>
    #     <% end %>
    #   <% end %>
    #
    # @example HTML attribute
    #   <%= tabler_ui.card_group html: { class: "mb-4" } do |slots| %>
    #     <% slots.body do %>...<% end %>
    #   <% end %>
    class Component
      include TablerUi::Base

      # @param options [Hash]
      # @option options [Hash] :html HTML attributes for the outer `.card-group` (part :root)
      def initialize(options = {})
        initialize_html_options(options)
      end

      # @return [Hash] attributes for the outer element (part :root)
      def root_attributes
        html_for(:root, class: "card-group")
      end
    end
  end
end
