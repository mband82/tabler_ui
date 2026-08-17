# frozen_string_literal: true

require "zlib"

module TablerUi
  module Avatar
    # Avatar component for Tabler UI. Renders one of three things, in order
    # of precedence:
    #
    #   1. image:    a <span class="avatar"> with a CSS background-image
    #   2. initials: a <span class="avatar"> with the initials text and an
    #                HSL background colour derived from the initials' bytes
    #   3. otherwise: a deterministic generated identicon <svg>, seeded from
    #                Zlib.crc32(name) -- see #identicon_shapes for the RNG
    #                scoping that fixes a global-state bug this component
    #                used to have.
    #
    # An `overlay` slot lets a caller nest a status dot or an avatar-brand
    # chip inside the root element (`.avatar` has `position: relative`, and
    # both overlays are `position: absolute`). Only supported on the image:
    # and initials: render modes -- an <svg> can't host an HTML overlay
    # without <foreignObject>, so passing an overlay to a generated
    # identicon raises ArgumentError.
    #
    #   <%= tabler_ui.avatar initials: "JD" do |slots| %>
    #     <% slots.overlay { tag.span(class: "badge bg-success") } %>
    #   <% end %>
    #
    # Status-dot trap: the per-size CSS that positions and sizes the dot
    # (`.avatar-{size} .badge:empty { ... }`) only matches a badge with *no*
    # child nodes -- including whitespace text nodes. Render it with
    # `tag.span(class: "badge bg-success")` and no block; a `do...end` block
    # (even an empty-looking one) leaves a newline inside the tag and the
    # badge silently falls back to a flat, unsized 10px dot. `badge-dot`
    # does not help either -- it's hardcoded to 10px and ignores
    # `--tblr-avatar-status-size`.
    #
    # @example Initials
    #   <%= tabler_ui.avatar initials: "JD", size: "md" %>
    #
    # @example Image (takes precedence over initials/name)
    #   <%= tabler_ui.avatar image: user_avatar_url(@user), size: "lg" %>
    #
    # @example Generated identicon, seeded from name
    #   <%= tabler_ui.avatar name: "Ada Lovelace" %>
    #
    # @example With details
    #   <%= tabler_ui.avatar initials: "JD", show_details: true, title: "Jane Doe", subtitle: "Admin" %>
    #
    # @example Rule 5 hooks on the root <span>/<svg> and the details <div>
    #   <%= tabler_ui.avatar initials: "JD", html: { class: "me-2" }, show_details: true, details_html: { class: "ms-1" } %>
    class Component
      include TablerUi::Base

      attr_reader :initials, :image, :title, :subtitle

      # @param options [Hash]
      # @option options [String] :initials     Initials text (e.g. "JD"). Ignored when :image is given.
      # @option options [String] :name         Seeds the generated identicon when neither :image nor :initials is given.
      # @option options [String] :image        Image URL. Takes precedence over :initials and :name.
      # @option options [String, Symbol] :size  Avatar size, rendered as avatar-<size> (default: "sm")
      # @option options [String, Symbol] :shape Avatar shape, rendered as rounded-<shape>
      #   (default: "rounded" for image/initials, "rounded-0" for the generated identicon)
      # @option options [Boolean] :show_details Render a title/subtitle block next to the avatar
      # @option options [String] :title         Shown in the details block
      # @option options [String] :subtitle      Shown in the details block
      # @option options [Boolean] :cover        Adds avatar-cover, the "overlaps the card header" modifier
      # @option options [Hash]   :html          Rule 5 HTML hook for the root <span>/<svg> (part :root)
      # @option options [Hash]   :details_html  Rule 5 HTML hook for the show_details wrapper <div> (part :details)
      def initialize(options = {})
        @initials = options[:initials]
        @name = options[:name].to_s
        @image = options[:image]
        @size = options[:size]
        @shape = options[:shape]
        @show_details = options[:show_details]
        @title = options[:title]
        @subtitle = options[:subtitle]
        @cover = options[:cover]

        initialize_html_options(options)
      end

      # @return [Boolean] whether an image URL was supplied. Takes precedence
      #   over :initials and :name.
      def image?
        @image.present?
      end

      # @return [Boolean] whether the initials mode applies (only when no image).
      def initials?
        !image? && @initials.present?
      end

      # @return [Boolean] whether neither image: nor initials: was given, i.e.
      #   the generated-identicon <svg> mode.
      def generated?
        !image? && !initials?
      end

      # @return [Boolean]
      def show_details?
        @show_details.present?
      end

      # @return [Boolean] whether to add the avatar-cover modifier, which
      #   pulls the avatar up over a card header via negative margin.
      def cover?
        @cover.present?
      end

      # @return [String] hsl() background colour derived from the initials' byte sum.
      def initials_color
        seed = @initials.to_s.bytes.sum % 360
        "hsl(#{seed}, 70%, 60%)"
      end

      # Deterministic filler shapes for the generated identicon.
      #
      # Bug fix: this used to seed Ruby's *global* RNG with `srand(seed)` and
      # call the bare `rand`/`Array#sample`, which perturbs every other
      # `rand` call in the process (sessions, other components, other specs)
      # on every single avatar render. Now scoped to a private
      # `Random.new(seed)` instance that lives only for the duration of this
      # call -- nothing global is touched. The colour sequence a given name
      # produces changes as a result (Random.new's stream differs from
      # srand's), but it stays deterministic: the same name always yields
      # the same shapes.
      #
      # @return [Array<Hash>]
      def identicon_shapes
        rng = Random.new(Zlib.crc32(@name))

        5.times.map do
          {
            type: %i[circle rect].sample(random: rng),
            cx: rng.rand(0..40),
            cy: rng.rand(0..40),
            r: rng.rand(5..12),
            size: rng.rand(10..25),
            fill: rand_color(rng),
            rotate: rng.rand(360)
          }
        end
      end

      # @return [String] avatar-<size>, defaulting to avatar-sm
      def size_class
        "avatar-#{@size || "sm"}"
      end

      # @return [String] rounded-<shape>, defaulting to "rounded" for
      #   image/initials and "rounded-0" for the generated identicon.
      def shape_class
        return "rounded-#{@shape}" if @shape.present?

        generated? ? "rounded-0" : "rounded"
      end

      # @return [Hash] attributes for the root <span>/<svg> (part :root),
      #   merged with whatever the caller supplied via html:. The
      #   background-image: url(...) / background-color: ... declarations
      #   are folded into this hash's :style so a caller-supplied html: {
      #   style: ... } (ordinary overwrite semantics, per rule 5) replaces
      #   them rather than being silently clobbered by a second .merge done
      #   in the template. The image URL is only ever placed inside an
      #   attribute value built by `tag.span`, which HTML-escapes it like
      #   any other attribute -- it can't break out of the attribute.
      def root_attributes
        classes = ["avatar", size_class, shape_class]
        classes << "avatar-cover" if cover?

        defaults = { class: classes.join(" ") }
        style = background_style
        defaults[:style] = style if style

        html_for(:root, defaults)
      end

      # @return [Hash] attributes for the show_details wrapper <div> (part
      #   :details), merged with whatever the caller supplied via
      #   details_html:. Only relevant when #show_details? is true.
      def details_attributes
        html_for(:details, class: "d-none d-xl-block ps-2")
      end

      private

      # @return [String, nil]
      def background_style
        return "background-image: url(#{@image})" if image?
        return "background-color: #{initials_color};" if initials?

        nil
      end

      # Deterministic randomish HSL colour, drawn from +rng+ -- an
      # instance-scoped Random passed in by #identicon_shapes, never the
      # process-global one. Bug fix: this method used to be `def rand_color`
      # defined directly inside the ERB template body. ERB templates compile
      # to methods on the (shared) view class, so that definition
      # redefined an instance method on ActionView::Base's subclass on
      # every single render. Living here, as a private method on this
      # component class, it's defined exactly once, like any other method.
      def rand_color(rng)
        "hsl(#{rng.rand(360)}, #{rng.rand(40..80)}%, #{rng.rand(40..70)}%)"
      end
    end
  end
end
