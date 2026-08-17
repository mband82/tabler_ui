# frozen_string_literal: true

module TablerUi
  # Marker module included by converted component classes.
  #
  # Named `Base` (not `Component`) because a component's own class is already
  # `TablerUi::<Name>::Component` — `TablerUi::Component` would collide with that.
  #
  # Including this module signals to the dispatcher (`TablerUi::Ui`) that the
  # component follows the new convention: mandatory arguments positional,
  # optional arguments in a trailing `options = {}` hash, and rule 5 HTML hooks
  # handled via `initialize_html_options` / `html_for`.
  module Base
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Class-level API mixed into any class that includes TablerUi::Base.
    module ClassMethods
      # Declare that this component's block yields the component itself
      # (builder style, e.g. Navbar/Dropdown/Tabs) rather than a SlotContext.
      def builder_style!
        @builder_style = true
      end

      # Whether this component uses the builder-style block (see #builder_style!).
      # Defaults to false, and does not leak across classes — each class gets
      # its own singleton ivar, so subclasses/siblings are unaffected unless
      # they call builder_style! themselves.
      def builder_style?
        @builder_style || false
      end
    end

    # Scans +options+ for rule 5 HTML-hook keys and stores them for later
    # retrieval via #html_for. The key :html maps to the :root part; any key
    # matching /_html\z/ maps to the part named by its prefix (:header_html
    # -> :header). Nil values are ignored. Call this from the component's
    # constructor.
    def initialize_html_options(options)
      @tabler_ui_html_options = {}
      return @tabler_ui_html_options if options.nil?

      options.each do |key, value|
        next if value.nil?

        key_s = key.to_s
        part =
          if key_s == "html"
            :root
          elsif key_s.end_with?("_html")
            key_s.delete_suffix("_html").to_sym
          end

        @tabler_ui_html_options[part] = value if part
      end

      @tabler_ui_html_options
    end

    # Guards a builder method's mandatory leading argument.
    #
    # Before rule 4, builders took keyword arguments -- `item(title: "General")`.
    # They now take positionals -- `item("General")`. Ruby collapses a stale
    # keyword call into a Hash and binds it to the positional without
    # complaint, so the component silently renders `{title: "General"}` as its
    # content instead of failing. That is the worst kind of migration bug: it
    # looks like it worked. Raise instead.
    #
    #   def item(title, options = {})
    #     builder_argument!(title, :title, builder: :item)
    def builder_argument!(value, name, builder:)
      return value unless value.is_a?(Hash)

      component = self.class.name.to_s.sub(/::Component\z/, "").demodulize.underscore

      raise ArgumentError,
            "#{component}##{builder} takes #{name} positionally: " \
            "#{builder}(#{name.to_s.inspect}), not #{builder}(#{name}: ...)"
    end

    # Returns +defaults+ merged with whatever HTML attrs the caller supplied
    # for +part+ (via the :html / :<part>_html hook), using
    # TablerUi::HtmlOptions.merge_html's contract. Safe to call even if
    # initialize_html_options was never invoked.
    #
    # A hook may also be a callable, for parts that repeat -- table rows,
    # datagrid items, nav entries -- so the caller can vary attributes per
    # item. Any extra arguments are passed to it:
    #
    #   tabler_ui.table row_html: ->(row) { { class: ("text-danger" if row.overdue?) } }
    #   # component side:
    #   html_for(:row, { class: "table-row" }, row)
    #
    # A callable returning nil is treated as an empty hash.
    def html_for(part, defaults = {}, *args)
      stored = (@tabler_ui_html_options || {})[part]
      stored = stored.call(*args) if stored.respond_to?(:call)

      TablerUi::HtmlOptions.merge_html(defaults, stored)
    end
  end
end
