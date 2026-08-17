# frozen_string_literal: true

module TablerUi
  module Spinner
    # Loading spinner component for Tabler UI.
    #
    # @example Basic usage (defaults to spinner-border)
    #   <%= tabler_ui.spinner %>
    #
    # @example Grow variant
    #   <%= tabler_ui.spinner type: :grow %>
    #
    # @example Small, colored
    #   <%= tabler_ui.spinner size: "sm", color: "blue" %>
    #
    # @example Custom accessible label
    #   <%= tabler_ui.spinner label: "Saving..." %>
    #
    # @example Rule 5 hook on the root <div>
    #   <%= tabler_ui.spinner html: { class: "me-2" } %>
    class Component
      include TablerUi::Base

      TYPES = %i[border grow].freeze

      attr_reader :type, :size, :color, :label

      # @param options [Hash]
      # @option options [Symbol, String] :type  :border (default) or :grow --
      #   raises ArgumentError naming the component and the valid values for
      #   anything else.
      # @option options [String, Symbol] :size  "sm" -- renders
      #   spinner-<type>-sm
      # @option options [String] :color Tabler palette / Bootstrap semantic
      #   colour name, validated via TablerUi::Color (raises ArgumentError if
      #   unknown). Rendered as text-<color>, since the spinner's CSS border
      #   colour is `currentcolor`. nil (the default) renders no colour class.
      # @option options [String] :label Visually-hidden text for screen
      #   readers, read out via role="status". Defaults to a translated
      #   "Loading..." (see config/locales/en.yml, tabler_ui.spinner.label).
      # @option options [Hash] :html Rule 5 HTML hook for the root <div> (part :root)
      def initialize(options = {})
        @type = validate_type(options[:type])
        @size = options[:size]
        @color = TablerUi::Color.validate!(options[:color], context: "spinner")
        @label = options.fetch(:label, I18n.t("tabler_ui.spinner.label"))

        initialize_html_options(options)
      end

      # @return [Hash] attributes for the root <div> (part :root), merged
      #   with whatever the caller supplied via html:. Carries role="status",
      #   since the accessible label lives inside this element.
      def root_attributes
        html_for(:root, class: spinner_classes, role: "status")
      end

      private

      def spinner_classes
        classes = ["spinner-#{@type}"]
        classes << "spinner-#{@type}-#{@size}" if @size.present?
        classes << "text-#{@color}" if @color.present?

        classes.join(" ")
      end

      def validate_type(value)
        return :border if value.nil?

        type = value.to_sym
        return type if TYPES.include?(type)

        raise ArgumentError,
              "unknown spinner type #{value.inspect} — valid: #{TYPES.join(', ')}"
      end
    end
  end
end
