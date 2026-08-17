# frozen_string_literal: true

module TablerUi
  module Icon
    # Icon component for Tabler UI. Reads a raw Tabler SVG icon off disk (gem
    # assets first, then the host app's app/assets/icons/<variant>/ as an
    # override hook) and emits it with `raw`.
    #
    # @example Basic usage
    #   <%= tabler_ui.icon icon: "user" %>
    #
    # @example Filled variant, colored, animated
    #   <%= tabler_ui.icon icon: "heart", filled: true, color: "danger", pulse: true %>
    #
    # @example Rule 5 hook on the root <svg>
    #   <%= tabler_ui.icon icon: "user", html: { class: "me-2", data: { testid: "user-icon" } } %>
    class Component
      include TablerUi::Base
      # Only used for TagBuilder#attributes below, to serialize the merged
      # root-tag attribute hash the same way Rails' own `tag` helper would
      # (handles class arrays, data-/aria-* hashes, escaping, ...). No new
      # runtime dependency: ActionView ships with the engine already.
      include ActionView::Helpers::TagHelper

      # Matches only the SVG's opening root tag, anchored to the start of the
      # file. Used with String#match (not #gsub) so exactly one, bounded
      # rewrite happens -- see #rewrite_root_tag.
      ROOT_SVG_TAG = /\A<svg\b[^>]*>/m

      # Matches a single name="value" attribute pair inside an opening tag.
      ATTRIBUTE = /([a-zA-Z_:][-\w:.]*)\s*=\s*"([^"]*)"/

      # @param icon [String] Tabler icon name, e.g. "user". Interpolated into
      #   a filesystem path, so it must not contain "/" or "..".
      # @param options [Hash]
      # @option options [Boolean] :filled Use the filled variant instead of outline (default: false)
      # @option options [String]  :color  Tabler color name, rendered as "text-<color>" on the root svg
      # @option options [Boolean] :pulse  Adds the "icon-pulse" animation class
      # @option options [Boolean] :tada   Adds the "icon-tada" animation class
      # @option options [Boolean] :rotate Adds the "icon-rotate" animation class
      # @option options [String]  :size   Rendered as "icon-<size>" on the root svg
      # @option options [String]  :title  Rendered as a title="..." attribute on the root svg
      # @option options [Hash]    :html   Rule 5 HTML hook for the root <svg> element
      def initialize(icon, options = {})
        @icon = icon
        @filled = options[:filled]
        @color = options[:color]
        @pulse = options[:pulse]
        @tada = options[:tada]
        @rotate = options[:rotate]
        @size = options[:size]
        @title = options[:title]

        initialize_html_options(options)
      end

      # @return [String] the icon's SVG markup, or the fallback bug icon.
      def icon_data
        svg = read_svg
        return draw_error_icon unless svg

        rewrite_root_tag(svg)
      end

      private

      # --- lookup ---------------------------------------------------------

      def read_svg
        return nil if @icon.blank? || !safe_icon_name?

        path = icon_path
        path && File.read(path)
      end

      # Path-traversal guard. @icon comes straight from the caller and is
      # interpolated into a filesystem path in #icon_path below, so any name
      # carrying a path separator or ".." is rejected outright rather than
      # sanitised -- there is no legitimate icon name that needs either.
      def safe_icon_name?
        name = @icon.to_s
        !name.include?("/") && !name.include?("..")
      end

      def icon_path
        variant = @filled.present? ? "filled" : "outline"

        # Gem's own icons first, then the host app's override directory.
        gem_path = File.expand_path("../../../assets/icons/#{variant}/#{@icon}.svg", __dir__)
        return gem_path if File.exist?(gem_path)

        app_path = Rails.root.join("app", "assets", "icons", variant, "#{@icon}.svg")
        return app_path if File.exist?(app_path)

        nil
      end

      # --- rendering --------------------------------------------------------

      # Rewrites *only* the opening <svg ...> tag -- matched once via
      # String#match, never a global gsub -- so nested elements inside the
      # icon (e.g. the <path> children) are never touched. Everything from
      # that tag's closing ">" onward is passed through byte-for-byte.
      def rewrite_root_tag(svg)
        match = ROOT_SVG_TAG.match(svg)
        return svg unless match

        opening_tag = match[0]
        rest_of_file = svg[opening_tag.length..]

        "<svg #{root_attributes(opening_tag)}>#{rest_of_file}"
      end

      # Builds the final attribute hash for the root <svg>: the tag's own
      # existing attributes (width, viewBox, stroke, ... and its own class),
      # plus this component's computed classes/title, merged with whatever
      # the caller passed via the html: hook (rule 5 -- see TablerUi::Base
      # and TablerUi::HtmlOptions.merge_html: caller class is appended, other
      # attributes overwrite).
      def root_attributes(opening_tag)
        existing = parse_attributes(opening_tag)
        own_class = existing.delete("class")

        defaults = existing.transform_keys(&:to_sym)
        defaults[:title] = @title if @title.present?
        defaults[:class] = icon_classes(own_class)

        tag.attributes(html_for(:root, defaults))
      end

      def parse_attributes(opening_tag)
        opening_tag.scan(ATTRIBUTE).each_with_object({}) { |(name, value), attrs| attrs[name] = value }
      end

      # The icon's own classes: whatever was already baked into the SVG file,
      # plus the animation/size/color modifiers. This is the "base" class
      # string handed to html_for(:root, ...), which is what caller-supplied
      # html: { class: ... } gets appended to rather than replacing.
      def icon_classes(own_class)
        classes = [own_class]
        classes << "icon-pulse" if @pulse
        classes << "icon-tada" if @tada
        classes << "icon-rotate" if @rotate
        classes << "icon-#{@size}" if @size.present?
        classes << "text-#{@color}" if @color.present?
        classes.select(&:present?).join(" ")
      end

      def draw_error_icon
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="red" stroke-width="3"
  stroke-linecap="round" stroke-linejoin="round" class="icon icon-tabler icons-tabler-outline icon-tabler-bug icon-tada"><path stroke="none" d="M0
  0h24v24H0z" fill="none"/><path d="M9 9v-1a3 3 0 0 1 6 0v1" /><path d="M8 9h8a6 6 0 0 1 1 3v3a5 5 0 0 1 -10 0v-3a6 6 0 0 1 1 -3" /><path d="M3 13l4 0"
  /><path d="M17 13l4 0" /><path d="M12 20l0 -6" /><path d="M4 19l3.35 -2" /><path d="M20 19l-3.35 -2" /><path d="M4 7l3.75 2.4" /><path d="M20 7l-3.75
  2.4" /></svg>'
      end
    end
  end
end
