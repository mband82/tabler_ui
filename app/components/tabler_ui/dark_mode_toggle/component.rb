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
    # @example Rule 5 hooks on the root <div> and the <a>
    #   <%= tabler_ui.dark_mode_toggle html: { class: "me-2" }, link_html: { data: { testid: "theme-toggle" } } %>
    class Component
      include TablerUi::Base

      # @param options [Hash]
      # @option options [Symbol] :size  :sm / :lg -- drives the SVG icons' pixel dimensions (default: 24)
      # @option options [String] :title Rendered as title="..." on the <a> (default: "Theme wechseln")
      # @option options [Hash]   :html      Rule 5 HTML hook for the outer <div> (part :root)
      # @option options [Hash]   :link_html Rule 5 HTML hook for the <a> (part :link)
      def initialize(options = {})
        @size = options[:size]
        @title = options.fetch(:title, "Theme wechseln")

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

      # @return [Hash] attributes for the <a> (part :link), merged with
      #   whatever the caller supplied via link_html:.
      def link_attributes
        html_for(:link,
                 class: "nav-link px-0",
                 href: "#",
                 title: @title,
                 data: { action: "click->tabler-ui--dark-mode#toggle" })
      end
    end
  end
end
