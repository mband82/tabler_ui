# frozen_string_literal: true

module TablerUi
  module Helper
    # Returns an instance of the TablerUi::Ui class for rendering components
    #
    # @example Using the navbar component
    #   <%= tabler_ui.navbar do |navbar| %>
    #     <% navbar.left do |nav| %>
    #       <% nav.add "Home", root_path %>
    #     <% end %>
    #   <% end %>
    def tabler_ui
      @tabler_ui ||= TablerUi::Ui.new(self)
    end

    # Form helper that uses TablerUi::FormBuilder by default
    #
    # @param options [Hash] form options (same as form_with)
    # @yield [TablerUi::FormBuilder] form builder instance
    #
    # @example Basic usage
    #   <%= tabler_form_with model: @user do |f| %>
    #     <%= f.input :name %>
    #     <%= f.input :email %>
    #     <%= f.submit "Save" %>
    #   <% end %>
    #
    # @example With custom options
    #   <%= tabler_form_with url: users_path, method: :post do |f| %>
    #     <%= f.input :name %>
    #   <% end %>
    def tabler_form_with(**options, &block)
      options[:builder] ||= TablerUi::FormBuilder
      form_with(**options, &block)
    end

    def tabler_ui_form_for(record, options = {}, &block)
      options[:builder] ||= TablerUi::FormBuilder
      form_for(record, options, &block)
    end
  end
end
