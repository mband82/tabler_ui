# frozen_string_literal: true

module TablerUi
  module Dimmer
    # Loading overlay for Tabler UI. Renders a `.dimmer` wrapper around a
    # `.dimmer-content` part; toggling `active:` on adds the `.dimmer.active`
    # class, which is what Tabler's CSS uses to show the `.loader` spinner and
    # drop the content's opacity to 0.1.
    #
    # This is a plain server-side toggle, not a Stimulus controller: the
    # caller flips `active:` and re-renders (e.g. after a Turbo Stream update
    # once a background job finishes) rather than the component managing its
    # own state client-side.
    #
    # @example Basic usage
    #   <%= tabler_ui.dimmer active: @loading do |slots| %>
    #     <% slots.content do %>Table rows go here<% end %>
    #   <% end %>
    #
    # @example Rule 5 hooks
    #   <%= tabler_ui.dimmer active: true, html: { class: "mb-4" },
    #                         loader_html: { class: "text-primary" },
    #                         content_html: { class: "p-3" } do |slots| %>
    #     <% slots.content do %>Content<% end %>
    #   <% end %>
    #
    # Note: the block yields exactly one argument, the SlotContext --
    # `do |slots|`, not `do |dimmer, slots|`.
    class Component
      include TablerUi::Base

      attr_reader :active

      # @param options [Hash]
      # @option options [Boolean] :active Adds `.active`, which shows the
      #   `.loader` and dims `.dimmer-content` down to 10% opacity
      #   (default: false).
      # @option options [Hash] :html         Rule 5 HTML hook for the outer `.dimmer` (part :root)
      # @option options [Hash] :loader_html  Rule 5 HTML hook for the `.loader` (part :loader)
      # @option options [Hash] :content_html Rule 5 HTML hook for the `.dimmer-content` (part :content)
      def initialize(options = {})
        @active = options[:active] || false

        initialize_html_options(options)
      end

      # @return [Boolean] whether the overlay is currently showing
      def active?
        @active
      end

      # @return [Hash] attributes for the outer element (part :root). Carries
      #   `aria-busy`, since a region that is loading should say so.
      def root_attributes
        html_for(:root, class: root_classes, aria: { busy: active? ? "true" : "false" })
      end

      # @return [Hash] attributes for the `.loader` (part :loader). Carries
      #   `role="status"`, since the visually-hidden text inside it is the
      #   loader's accessible name.
      def loader_attributes
        html_for(:loader, class: "loader", role: "status")
      end

      # @return [Hash] attributes for the `.dimmer-content` (part :content)
      def content_attributes
        html_for(:content, class: "dimmer-content")
      end

      # @return [String] visually-hidden text announced by the loader's
      #   role="status" while active.
      def loader_label
        I18n.t("tabler_ui.dimmer.loader_label")
      end

      private

      def root_classes
        classes = ["dimmer"]
        classes << "active" if active?
        classes.join(" ")
      end
    end
  end
end
