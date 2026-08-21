# frozen_string_literal: true

module TablerUi
  module DarkModeToggle
    # Light/dark/system theme toggle for Tabler UI. Renders a single button
    # wired up to the `tabler-ui--dark-mode` Stimulus controller
    # (app/javascript/controllers/tabler_ui/dark_mode_controller.js), which
    # reads/writes localStorage and toggles which of the three inline SVG
    # icons is visible.
    #
    # @example Basic usage
    #   <%= tabler_ui.dark_mode_toggle %>
    #
    # @example Small icons, custom title
    #   <%= tabler_ui.dark_mode_toggle size: :sm, title: "Switch theme" %>
    #
    # @example Rule 5 hooks on the root <div> and the <button>
    #   <%= tabler_ui.dark_mode_toggle html: { class: "me-2" }, button_html: { data: { testid: "theme-toggle" } } %>
    class Component
      include TablerUi::Base

      # @param options [Hash]
      # @option options [Symbol] :size  :sm / :lg -- drives the SVG icons' pixel dimensions (default: 24)
      # @option options [String] :title Rendered as title="..." on the <button> (default: "Switch theme")
      # @option options [Hash]   :html        Rule 5 HTML hook for the outer <div> (part :root)
      # @option options [Hash]   :button_html Rule 5 HTML hook for the <button> (part :button)
      def initialize(options = {})
        @size = options[:size]
        @title = options.fetch(:title, I18n.t("tabler_ui.dark_mode_toggle.title"))

        initialize_html_options(options)
      end

      # @return [Integer] pixel width/height for the three SVG icons.
      def icon_size
        case @size
        when :sm then 16
        when :lg then 32
        else 24
        end
      end

      # @return [Hash] attributes for the outer <div> (part :root), merged
      #   with whatever the caller supplied via html:.
      def root_attributes
        html_for(:root, class: "d-inline-block", data: { controller: "tabler-ui--dark-mode" })
      end

      # @return [Hash] attributes for the <button> (part :button), merged
      #   with whatever the caller supplied via button_html:.
      #
      # A <button type="button">, not an <a href="#">: this toggle has no
      # destination, and an anchor with a bare "#" href is a real link click
      # as far as Turbo Drive is concerned -- it gets intercepted and turned
      # into a full page visit (fetch back to the same URL, DOM swap) on
      # every click, tearing down and rebuilding every Stimulus controller on
      # the page for what should be a purely client-side toggle. A <button>
      # is not a link, so nothing but the click->toggle action fires, and it
      # is keyboard-accessible (Enter/Space) with no extra work.
      def button_attributes
        html_for(:button,
                 class: "nav-link px-0",
                 type: "button",
                 title: @title,
                 data: { action: "click->tabler-ui--dark-mode#toggle" })
      end
    end
  end
end
