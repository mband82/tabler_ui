# frozen_string_literal: true

module TablerUi
  module Illustration
    # Illustration component for Tabler UI. Reads a raw Tabler illustration SVG
    # off disk (gem assets first, then the host app's
    # app/assets/illustrations/<theme>/ as an override hook) and emits it with
    # `raw`.
    #
    # @example Basic usage
    #   <%= tabler_ui.illustration name: "empty" %>
    #
    # @example Dark theme, sized
    #   <%= tabler_ui.illustration name: "empty", theme: "dark", size: :lg %>
    #
    # @example Rule 5 hook on the root <svg>
    #   <%= tabler_ui.illustration name: "empty", html: { class: "me-2", data: { testid: "empty-illustration" } } %>
    class Component
      include TablerUi::Base
      # Only used for TagBuilder#attributes below, to serialize the merged
      # root-tag attribute hash the same way Rails' own `tag` helper would
      # (handles class arrays, data-/aria-* hashes, escaping, ...). No new
      # runtime dependency: ActionView ships with the engine already.
      include ActionView::Helpers::TagHelper

      SIZES = {
        xs: 100,
        sm: 150,
        md: 200,
        lg: 300,
        xl: 400,
        xxl: 600
      }.freeze

      # Matches only the SVG's opening root tag, anchored to the start of the
      # file. Used with String#match (not #gsub) so exactly one, bounded
      # rewrite happens -- see #rewrite_root_tag.
      ROOT_SVG_TAG = /\A<svg\b[^>]*>/m

      # Matches a single name="value" attribute pair inside an opening tag.
      ATTRIBUTE = /([a-zA-Z_:][-\w:.]*)\s*=\s*"([^"]*)"/

      # @param name [String] Tabler illustration name, e.g. "empty". Interpolated
      #   into a filesystem path, so it must not contain "/" or "..".
      # @param options [Hash]
      # @option options [String]        :theme Asset folder to load from: "light" or "dark" (default: "light")
      # @option options [String,Symbol,Integer] :size Named size (:xs..:xxl) or a raw pixel width;
      #   height is scaled proportionally from the source viewBox
      # @option options [Hash]          :html  Rule 5 HTML hook for the root <svg> element
      def initialize(name, options = {})
        @name = name
        @theme = options.fetch(:theme, "light")
        @size = options[:size]

        initialize_html_options(options)
      end

      # @return [String] the illustration's SVG markup, or the fallback "not found" SVG.
      def illustration_data
        svg = read_svg
        return draw_error_illustration unless svg

        rewrite_root_tag(svg)
      end

      private

      # --- lookup ---------------------------------------------------------

      def read_svg
        return nil if @name.blank? || !safe_illustration_name?

        path = illustration_path
        path && File.read(path)
      end

      # Path-traversal guard. @name comes straight from the caller and is
      # interpolated into a filesystem path in #illustration_path below, so
      # any name carrying a path separator or ".." is rejected outright
      # rather than sanitised -- there is no legitimate illustration name
      # that needs either.
      def safe_illustration_name?
        name = @name.to_s
        !name.include?("/") && !name.include?("..")
      end

      def illustration_path
        # Gem's own illustrations first, then the host app's override directory.
        gem_path = File.expand_path("../../../assets/illustrations/#{@theme}/#{@name}.svg", __dir__)
        return gem_path if File.exist?(gem_path)

        app_path = Rails.root.join("app", "assets", "illustrations", @theme, "#{@name}.svg")
        return app_path if File.exist?(app_path)

        nil
      end

      # --- rendering --------------------------------------------------------

      # Rewrites *only* the opening <svg ...> tag -- matched once via
      # String#match, never a global gsub -- so nested elements inside the
      # illustration are never touched. Everything from that tag's closing
      # ">" onward is passed through byte-for-byte.
      def rewrite_root_tag(svg)
        match = ROOT_SVG_TAG.match(svg)
        return svg unless match

        opening_tag = match[0]
        rest_of_file = svg[opening_tag.length..]

        "<svg #{root_attributes(opening_tag)}>#{rest_of_file}"
      end

      # Builds the final attribute hash for the root <svg>: the tag's own
      # existing attributes (width, viewBox, ... and its own class), with
      # width/height overridden per the :size option, merged with whatever
      # the caller passed via the html: hook (rule 5 -- see TablerUi::Base
      # and TablerUi::HtmlOptions.merge_html: caller class is appended, other
      # attributes overwrite).
      def root_attributes(opening_tag)
        existing = parse_attributes(opening_tag)
        own_class = existing.delete("class")
        view_box = existing["viewBox"]

        defaults = existing.transform_keys(&:to_sym)
        defaults.merge!(sized_dimensions(view_box))
        defaults[:class] = illustration_classes(own_class)

        tag.attributes(html_for(:root, defaults))
      end

      def parse_attributes(opening_tag)
        opening_tag.scan(ATTRIBUTE).each_with_object({}) { |(name, value), attrs| attrs[name] = value }
      end

      # The illustration's own classes: the shipped assets carry no class on
      # their root <svg> at all, so "illustration" is added here as a stable
      # base class -- this is the "base" class string handed to
      # html_for(:root, ...), which is what caller-supplied html: { class: ... }
      # gets appended to rather than replacing.
      def illustration_classes(own_class)
        [own_class, "illustration"].select(&:present?).join(" ")
      end

      # Computes a pixel width/height pair for the :size option, scaling
      # height proportionally from the source viewBox's aspect ratio. Returns
      # {} (leaving the SVG's own width/height untouched) when :size wasn't
      # given or the viewBox can't be parsed.
      def sized_dimensions(view_box)
        return {} unless @size.present?

        match = view_box.to_s.match(/\A0 0 (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)\z/)
        return {} unless match

        orig_width = match[1].to_f
        orig_height = match[2].to_f
        width = SIZES[@size.to_s.to_sym] || @size.to_i
        height = (width * orig_height / orig_width).round

        { width: width, height: height }
      end

      def draw_error_illustration
        <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" width="200" height="150" viewBox="0 0 200 150" class="illustration-error">
            <rect width="200" height="150" fill="#f8d7da" rx="8"/>
            <text x="100" y="70" text-anchor="middle" fill="#721c24" font-size="14">Illustration</text>
            <text x="100" y="90" text-anchor="middle" fill="#721c24" font-size="14">#{I18n.t('tabler_ui.illustration.not_found')}</text>
            <text x="100" y="115" text-anchor="middle" fill="#721c24" font-size="12" opacity="0.7">#{@name || I18n.t('tabler_ui.illustration.unknown')}</text>
          </svg>
        SVG
      end
    end
  end
end
