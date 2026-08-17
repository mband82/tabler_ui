# frozen_string_literal: true

module TablerUi
  class FormBuilder < ActionView::Helpers::FormBuilder
    delegate :tag, :safe_join, to: :@template

    def input(method, options = {})
      @form_options = options

      if options[:as] == :hidden
        return hidden_field(method, merge_input_options({}, options[:input_html]))
      end

      object_type = object_type_for_method(method)

      # :date, :integer, :decimal, :float, :datetime and :time all render
      # through string_input -> string_field, which does the finer-grained
      # dispatch on the real column type (see string_field below).
      input_type = case object_type
                   when :date, :integer, :decimal, :float, :datetime, :time then :string
                   else object_type
                   end

      override_input_type = if options[:as]
                              options[:as]
                            elsif options[:collection] && !%i[imagecheck color].include?(options[:as])
                              :select
                            end

      resolved_input_type = override_input_type || input_type
      input_method = "#{resolved_input_type}_input"

      # A column type we don't recognize (and that wasn't given an explicit
      # `as:`) would otherwise hit `send` with a method name nothing defines,
      # raising a bare NoMethodError. Fail with a message that names the
      # field and the type so the next developer knows what to add.
      unless respond_to?(input_method, true)
        raise ArgumentError,
              "TablerUi::FormBuilder#input doesn't know how to render #{method.inspect} " \
              "(column type #{object_type.inspect}, resolved input type #{resolved_input_type.inspect}). " \
              "Pass `as:` to render it explicitly (e.g. `as: :string`), or add a `##{input_method}` " \
              'method to TablerUi::FormBuilder.'
      end

      send(input_method, method, options)
    end

    # Naked input field without wrapper or label
    def input_field(method, options = {})
      if options[:as] == :hidden
        return hidden_field(method, merge_input_options({}, options[:input_html]))
      end

      object_type = object_type_for_method(method)
      input_options = merge_input_options(
        { class: "form-control #{'is-invalid' if has_error?(method)}" },
        options[:input_html]
      )

      case options[:as] || object_type
      when :text then text_area(method, input_options)
      when :boolean then check_box(method, merge_input_options({ class: 'form-check-input' }, options[:input_html]))
      when :file then file_field(method, input_options)
      when :select
        collection_select(method, options[:collection], options[:value_method] || :to_s,
                          options[:text_method] || :to_s, options,
                          merge_input_options({ class: "form-select #{'is-invalid' if has_error?(method)}" }, options[:input_html]))
      else
        string_field(method, input_options)
      end
    end

    # Association helper - detects belongs_to (select) and has_many (checkboxes)
    def association(method, options = {})
      if @object.class.respond_to?(:reflect_on_association)
        reflection = @object.class.reflect_on_association(method)
      end

      if reflection
        collection = options[:collection] || reflection.klass.all
        label_method = options[:label_method] || options[:text_method] || :to_s
        value_method = options[:value_method] || :id

        case reflection.macro
        when :belongs_to
          select_options = options.merge(
            collection: collection,
            value_method: value_method,
            text_method: label_method
          )
          foreign_key = reflection.foreign_key
          input(foreign_key, select_options)
        when :has_many, :has_and_belongs_to_many
          check_options = options.merge(
            collection: collection,
            value_method: value_method,
            text_method: label_method,
            as: :check_boxes
          )
          input(method, check_options)
        else
          input(method, options)
        end
      else
        # Fallback: treat as select with collection
        input(method, options)
      end
    end

    # Display model errors as a Tabler alert at the top of the form
    def error_notification(message: nil)
      return unless @object.respond_to?(:errors) && @object.errors.any?

      message ||= I18n.t('tabler_ui.form.error_notification')

      tag.div(class: 'alert alert-danger mb-3', role: 'alert') do
        safe_join [
          tag.h4(message, class: 'alert-title'),
          tag.div(class: 'text-secondary') do
            tag.ul do
              safe_join(@object.errors.full_messages.map { |msg| tag.li(msg) })
            end
          end
        ]
      end
    end

    def toggle_button(method, options = {})
      toggle_button_input(method, options)
    end

    def toggle_switch(method, options = {})
      toggle_switch_input(method, options)
    end

    private

    def normalize_collection(collection, value_method, text_method)
      case collection
      when Hash
        collection.map { |text, value| OpenStruct.new(text: text, value: value) }
      when Array
        if collection.first.is_a?(Array)
          collection.map { |text, value| OpenStruct.new(text: text, value: value) }
        elsif value_method != :to_s && collection.first.respond_to?(value_method)
          collection
        else
          collection
        end
      else
        collection
      end
    end

    def form_group(method, options = {}, &block)
      tag.div class: "mb-3 #{method}" do
        safe_join [
          block.call,
          hint_text(options[:hint]),
          error_text(method)
        ].compact
      end
    end

    def hint_text(text)
      return if text.nil?

      tag.small text, class: 'form-hint'
    end

    def label_with_description(method, options = {})
      label_text = options[:label] || method.to_s.humanize
      description = options[:label_description]
      required = options[:required]

      if description
        label(method, class: 'form-label') do
          safe_join [
            tag.span(label_text),
            (tag.span(' *', class: 'text-danger') if required),
            tag.span(description, class: 'form-label-description')
          ].compact
        end
      else
        label_class = required ? 'form-label required' : 'form-label'
        label(method, label_text, class: label_class)
      end
    end

    def error_text(method)
      return unless has_error?(method)

      tag.div(@object.errors[method].join('<br />').html_safe, class: 'invalid-feedback')
    end

    def object_type_for_method(method)
      result = if @object.respond_to?(:type_for_attribute) && @object.has_attribute?(method)
                 @object.type_for_attribute(method.to_s).try(:type)
               elsif @object.respond_to?(:column_for_attribute) && @object.has_attribute?(method)
                 @object.column_for_attribute(method).try(:type)
               end

      result || :string
    end

    def has_error?(method)
      return false unless @object.respond_to?(:errors)

      @object.errors.key?(method)
    end

    # Inputs and helpers

    def string_input(method, options = {})
      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          string_field(method,
                       merge_input_options({ class: "form-control #{if has_error?(method)
                                                                      'is-invalid'
                                                                    end}" }, options[:input_html]))
        ]
      end
    end

    def text_input(method, options = {})
      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          text_area(method,
                    merge_input_options({ class: "form-control #{if has_error?(method)
                                                                   'is-invalid'
                                                                 end}" }, options[:input_html]))
        ]
      end
    end

    def boolean_input(method, options = {})
      form_group(method, options) do
        tag.label(class: 'form-check') do
          safe_join [
            check_box(method, merge_input_options({ class: 'form-check-input' }, options[:input_html])),
            tag.span(options[:label] || method.to_s.humanize, class: 'form-check-label')
          ]
        end
      end
    end

    def collection_input(method, options, &block)
      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          block.call
        ]
      end
    end

    def select_input(method, options = {})
      value_method = options[:value_method] || :to_s
      text_method = options[:text_method] || :to_s
      collection = options[:collection]

      normalized = normalize_collection(collection, value_method, text_method)
      if normalized != collection
        collection = normalized
        value_method = :value
        text_method = :text
      end

      collection_input(method, options) do
        collection_select(method, collection, value_method, text_method, options,
                          merge_input_options({ class: "form-select #{if has_error?(method)
                                                                        'is-invalid'
                                                                      end}" }, options[:input_html]))
      end
    end

    def grouped_select_input(method, options = {})
      collection_input(method, options) do
        grouped_collection_select(method, options[:collection], :last, :first, :to_s, :to_s, options,
                                  merge_input_options({ class: "form-select #{if has_error?(method)
                                                                                'is-invalid'
                                                                              end}" }, options[:input_html]))
      end
    end

    def file_input(method, options = {})
      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          file_field(method,
                     merge_input_options({ class: "form-control #{if has_error?(method)
                                                                    'is-invalid'
                                                                  end}" }, options[:input_html]))
        ]
      end
    end

    def collection_of(input_type, method, options = {})
      form_builder_method, check_class, input_builder_method = case input_type
                                                               when :radio_buttons then [:collection_radio_buttons,
                                                                                         'form-check', :radio_button]
                                                               when :check_boxes then [:collection_check_boxes,
                                                                                       'form-check', :check_box]
                                                               else raise 'Invalid input_type for collection_of, valid input_types are ":radio_buttons", ":check_boxes"'
                                                               end

      use_selectgroup = options[:selectgroup] || options[:selectgroup_pills] || options[:selectgroup_buttons]

      value_method = options[:value_method] || :to_s
      text_method = options[:text_method] || :to_s
      collection = options[:collection]

      normalized = normalize_collection(collection, value_method, text_method)
      if normalized != collection
        collection = normalized
        value_method = :value
        text_method = :text
      end

      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          if use_selectgroup
            selectgroup_collection(form_builder_method, method, collection, value_method, text_method, options, input_builder_method)
          else
            tag.div(class: 'form-selectgroup') do
              send(form_builder_method, method, collection, value_method,
                   text_method) do |b|
                tag.label(class: check_class) do
                  safe_join [
                    b.send(input_builder_method, class: 'form-check-input'),
                    tag.span(b.text, class: 'form-check-label')
                  ]
                end
              end
            end
          end
        ]
      end
    end

    def selectgroup_collection(form_builder_method, method, collection, value_method, text_method, options, input_builder_method)
      selectgroup_class = ['form-selectgroup']
      selectgroup_class << 'form-selectgroup-pills' if options[:selectgroup_pills]
      selectgroup_class << 'form-selectgroup-boxes' if options[:selectgroup_buttons]

      tag.div(class: selectgroup_class.join(' ')) do
        send(form_builder_method, method, collection, value_method, text_method) do |b|
          tag.label(class: 'form-selectgroup-item') do
            safe_join [
              b.send(input_builder_method, class: 'form-selectgroup-input'),
              tag.span(b.text, class: 'form-selectgroup-label')
            ]
          end
        end
      end
    end

    def radio_buttons_input(method, options = {})
      collection_of(:radio_buttons, method, options)
    end

    def check_boxes_input(method, options = {})
      collection_of(:check_boxes, method, options)
    end

    # Date picker input - explicit datepicker with Stimulus controller
    def date_picker_input(method, options = {})
      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          text_field(method,
                     merge_input_options(
                       { class: "form-control #{'is-invalid' if has_error?(method)}",
                         data: { controller: 'tabler-ui--datepicker' },
                         autocomplete: 'off' },
                       options[:input_html]
                     ))
        ]
      end
    end

    def string_field(method, options = {})
      case object_type_for_method(method)
      when :date
        text_field(method,
                   merge_input_options(options,
                                       { data: { controller: 'tabler-ui--datepicker' }, "autocomplete": 'off' }))
      when :integer then number_field(method, options)
      when :decimal, :float
        # step: "any" rather than a fixed increment: a :decimal column's
        # scale isn't reliably available here (no guaranteed DB connection),
        # and a fixed step (e.g. "0.01") would make the browser reject
        # otherwise-valid values with more precision. A caller that wants a
        # specific step can still set input_html: { step: ... }, which wins
        # over this default (merge_input_options puts the default first).
        number_field(method, merge_input_options({ step: 'any' }, options))
      when :datetime
        # Native datetime-local input rather than routing through the
        # tabler-ui--datepicker Stimulus controller: that controller wraps
        # vanillajs-datepicker, a date-only picker with no time support, and
        # extending it is out of scope here. This needs no JS at all.
        datetime_local_field(method, options)
      when :time
        time_field(method, options)
      when :string
        case method.to_s
        when /password/ then password_field(method, options)
        when /email/ then email_field(method, options)
        when /phone/ then telephone_field(method, options)
        when /url/ then url_field(method, options)
        else
          text_field(method, options)
        end
      else
        # Any other/unhandled type still needs a widget when reached from
        # here (e.g. via #input_field, which has no equivalent of #input's
        # clear-error guard). A plain text field is the safest fallback --
        # better than silently rendering nothing.
        text_field(method, options)
      end
    end

    # Toggle switch input (alternative to checkbox)
    def toggle_input(method, options = {})
      form_group(method, options) do
        tag.label(class: 'form-check form-switch') do
          safe_join [
            check_box(method, merge_input_options({ class: 'form-check-input' }, options[:input_html])),
            tag.span(options[:label] || method.to_s.humanize, class: 'form-check-label')
          ]
        end
      end
    end

    # Toggle switch - styled switch with label and optional description
    def toggle_switch_input(method, options = {})
      switch_label = options[:label] == false ? nil : (options[:label] || method.to_s.humanize)
      description = options[:description]
      reverse = options[:reverse]
      size = options[:size]

      switch_classes = ["form-check", "form-switch"]
      switch_classes << "form-check-reverse" if reverse
      switch_classes << "form-switch-lg" if size == :lg

      form_group(method, options.merge(label: false)) do
        tag.label(class: switch_classes.join(" ")) do
          safe_join [
            check_box(method, merge_input_options({ class: "form-check-input" }, options[:input_html])),
            if description
              tag.span(class: "form-check-label") do
                safe_join [
                  switch_label,
                  tag.span(description, class: "form-check-description")
                ]
              end
            elsif switch_label
              tag.span(switch_label, class: "form-check-label")
            end
          ].compact
        end
      end
    end

    # Toggle button input - boolean as clickable button (filled when active, outline when inactive)
    def toggle_button_input(method, options = {})
      color = options.fetch(:color, "primary")
      button_text = options.fetch(:text, method.to_s.humanize)
      icon_name = options[:icon]
      size = options[:size]

      checked = @object.respond_to?(method) ? !!@object.send(method) : false

      btn_classes = ["btn"]
      btn_classes << "btn-#{size}" if size
      btn_classes << (checked ? "btn-#{color}" : "btn-outline-#{color}")

      icon_html = icon_name ? @template.tabler_ui.icon(icon: icon_name) : nil

      button_content = if icon_html && button_text.present?
                         safe_join([icon_html, " #{button_text}"])
                       elsif icon_html
                         icon_html
                       else
                         button_text
                       end

      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          tag.div(data: {
            controller: "tabler-ui--toggle-button",
            "tabler-ui--toggle-button-color-value": color
          }) do
            safe_join [
              hidden_field(method,
                           merge_input_options(
                             { value: checked ? "1" : "0",
                               data: { "tabler-ui--toggle-button-target": "input" } },
                             options[:input_html]
                           )),
              # Rule 5: button_html: is the hook for this element, merged so a
              # caller's class appends to the btn-* classes above rather than
              # replacing them. Replaces the old custom_class: option.
              tag.button(button_content, **merge_input_options(
                { type: "button",
                  class: btn_classes.join(" "),
                  data: {
                    "tabler-ui--toggle-button-target": "button",
                    action: "click->tabler-ui--toggle-button#toggle"
                  } },
                options[:button_html]
              ))
            ]
          end
        ].compact
      end
    end

    def rating_input(method, options = {})
      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          @template.tabler_ui.rating(
            name: "#{@object_name}[#{method}]",
            value: @object.send(method),
            id: "#{@object_name}_#{method}",
            required: options[:required],
            disabled: options[:disabled],
            size: options[:size],
            color: options[:color],
            tooltip: options[:tooltip],
            clearable: options[:clearable],
            max_stars: options[:max_stars],
            choices: options[:choices]
          )
        ]
      end
    end

    def color_input(method, options = {})
      colors = options[:colors] || %w[#206bc4 #4299e1 #0ca678 #f59f00 #d63939 #ae3ec9]
      value_method = options[:value_method] || :to_s

      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          tag.div(class: 'form-colorinput') do
            colors.map do |color|
              color_value = color.respond_to?(value_method) ? color.send(value_method) : color
              tag.label(class: 'form-colorinput-color', style: "background-color: #{color_value}") do
                radio_button(method, color_value, class: 'form-colorinput-input')
              end
            end.join.html_safe
          end
        ]
      end
    end

    # Image check input for image-based selections
    def imagecheck_input(method, options = {})
      collection = options[:collection] || []
      value_method = options[:value_method] || :to_s
      image_method = options[:image_method] || :image_url
      text_method = options[:text_method] || :to_s
      multiple = options[:multiple]

      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          tag.div(class: 'form-imagecheck') do
            collection.map do |item|
              value = item.respond_to?(value_method) ? item.send(value_method) : item
              image = item.respond_to?(image_method) ? item.send(image_method) : item
              text = item.respond_to?(text_method) ? item.send(text_method) : item.to_s

              tag.label(class: 'form-imagecheck-item') do
                safe_join [
                  if multiple
                    check_box(method, { class: 'form-imagecheck-input', multiple: true }, value, nil)
                  else
                    radio_button(method, value, class: 'form-imagecheck-input')
                  end,
                  tag.figure(class: 'form-imagecheck-figure') do
                    tag.img(src: image, alt: text, class: 'form-imagecheck-image')
                  end,
                  (tag.span(text, class: 'form-imagecheck-caption') if options[:show_text])
                ].compact
              end
            end.join.html_safe
          end
        ]
      end
    end

    def input_group(method, options = {})
      prepend = options[:prepend]
      append = options[:append]
      prepend_button = options[:prepend_button]
      append_button = options[:append_button]

      form_group(method, options) do
        safe_join [
          (label_with_description(method, options) unless options[:label] == false),
          tag.div(class: 'input-group') do
            safe_join [
              (tag.span(prepend, class: 'input-group-text') if prepend),
              (prepend_button if prepend_button),
              string_field(method,
                           merge_input_options({ class: "form-control #{if has_error?(method)
                                                                          'is-invalid'
                                                                        end}" }, options[:input_html])),
              (tag.span(append, class: 'input-group-text') if append),
              (append_button if append_button)
            ].compact
          end
        ]
      end
    end

    def floating_input(method, options = {})
      input_type = options[:type] || :text

      form_group(method, options) do
        tag.div(class: 'form-floating') do
          safe_join [
            if input_type == :textarea
              text_area(method, merge_input_options({
                                                      class: "form-control #{'is-invalid' if has_error?(method)}",
                                                      placeholder: options[:label] || method.to_s.humanize
                                                    }, options[:input_html]))
            else
              text_field(method, merge_input_options({
                                                       class: "form-control #{'is-invalid' if has_error?(method)}",
                                                       placeholder: options[:label] || method.to_s.humanize
                                                     }, options[:input_html]))
            end,
            label(method, options[:label] || method.to_s.humanize)
          ]
        end
      end
    end

    def merge_input_options(options, user_options)
      TablerUi::HtmlOptions.merge_html(options, user_options)
    end
  end
end
