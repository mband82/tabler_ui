# frozen_string_literal: true

module TablerUi
  module Datagrid
    # Datagrid component for Tabler UI. Renders a `.datagrid` of label/value
    # pairs, each a `.datagrid-item` with a `.datagrid-title` and
    # `.datagrid-content`. Builder-style: the block yields the component
    # itself, and items are added via `#item`.
    #
    # @example Basic usage
    #   <%= tabler_ui.datagrid do |dg| %>
    #     <% dg.item "Name", content: "Ada Lovelace" %>
    #     <% dg.item "Bio" do %>
    #       <strong>Mathematician</strong>
    #     <% end %>
    #   <% end %>
    #
    # @example items: passed directly at construction
    #   <%= tabler_ui.datagrid items: [{ title: "Name", content: "Ada" }] %>
    #
    # @example HTML attributes
    #   <%= tabler_ui.datagrid html: { class: "mb-4" },
    #                          item_html: ->(item) { item[:title] == "Name" ? { class: "fw-bold" } : {} },
    #                          title_html: { class: "text-muted" },
    #                          content_html: { class: "text-end" } do |dg| %>
    #     <% dg.item "Name", content: "Ada" %>
    #   <% end %>
    class Component
      include TablerUi::Base
      builder_style!

      # @param options [Hash]
      # @option options [Array<Hash>] :items Pre-built items, each a Hash with
      #   `:title` and `:content` (default: [])
      # @option options [Hash]           :html         HTML attributes for the outer `.datagrid` (part :root)
      # @option options [Hash, Proc]     :item_html    HTML attributes for each `.datagrid-item` (part :item).
      #   Either a plain Hash (applied to every item) or a callable taking the
      #   item and returning a Hash.
      # @option options [Hash, Proc]     :title_html   HTML attributes for each `.datagrid-title` (part :title)
      # @option options [Hash, Proc]     :content_html HTML attributes for each `.datagrid-content` (part :content)
      def initialize(options = {})
        # Construction-time items can't have their auth: resolved here: a
        # bare item Hash with no :auth of its own is meant to inherit the
        # datagrid's own auth: (CLAUDE.md rule 8), but `self.auth` isn't set
        # yet at this point -- TablerUi::Ui sets it via `.auth=` right after
        # `.new` returns (see ui.rb's build_modern_component call site), so
        # it's still nil/unset for the whole body of #initialize. Resolving
        # inheritance against that unset value here would silently bake in
        # the wrong answer. So construction-time items are kept raw in
        # @construction_items and filtered lazily by #items/#has_items?,
        # which run at render time -- after auth= has been set -- and can
        # therefore resolve inheritance correctly.
        @construction_items = options[:items] || []
        @items = []

        initialize_html_options(options)
      end

      # Adds an item to the datagrid.
      #
      # @param title [String] mandatory item title
      # @param options [Hash]
      # @option options [String] :content Item content. Ignored if a block is given.
      # @option options [Object] :auth Per-item authorization value (CLAUDE.md
      #   rule 8) -- checked against the globally configured auth_method.
      #   Defaults to the datagrid's own :auth when omitted. An unauthorized
      #   item is not appended.
      # @param block [Proc] Item content, captured at render time. Takes
      #   precedence over options[:content] when both are given.
      # @return [nil] if :auth denied the item (no-op)
      def item(title, options = {}, &block)
        effective_auth = options.key?(:auth) ? options[:auth] : auth
        return unless TablerUi::Authorization.authorized?(effective_auth)

        builder_argument!(title, :title, builder: :item)

        @items << {
          title: title,
          content: options[:content],
          block: block,
          auth: effective_auth,
        }
      end

      # @return [Array<Hash>] every authorized item -- construction-time
      #   items (auth: resolved lazily, see #initialize) followed by items
      #   added via #item (already resolved/filtered when #item ran).
      def items
        authorized_construction_items + @items
      end

      # @return [Boolean] whether there are any items to render
      def has_items?
        items.any?
      end

      # @return [Hash] attributes for the outer element (part :root)
      def root_attributes
        html_for(:root, class: "datagrid")
      end

      # @param item [Hash] the current item being rendered
      # @return [Hash] attributes for this item's wrapper (part :item)
      def item_attributes(item)
        html_for(:item, { class: "datagrid-item" }, item)
      end

      # @param item [Hash] the current item being rendered
      # @return [Hash] attributes for this item's title (part :title)
      def title_attributes(item)
        html_for(:title, { class: "datagrid-title" }, item)
      end

      # @param item [Hash] the current item being rendered
      # @return [Hash] attributes for this item's content (part :content)
      def content_attributes(item)
        html_for(:content, { class: "datagrid-content" }, item)
      end

      private

      # Resolves each construction-time item's effective auth: (its own
      # :auth key if present, else the datagrid's own auth:) and filters out
      # the unauthorized ones. Recomputed on every call rather than
      # memoized -- item lists here are small, and `auth` is set once by the
      # dispatcher before rendering, so there's no correctness reason to
      # cache. Returns fresh Hashes (via #merge) rather than mutating the
      # caller's original item Hashes.
      def authorized_construction_items
        @construction_items.filter_map do |item_hash|
          effective_auth = item_hash.key?(:auth) ? item_hash[:auth] : auth
          next unless TablerUi::Authorization.authorized?(effective_auth)

          item_hash.merge(auth: effective_auth)
        end
      end
    end
  end
end
