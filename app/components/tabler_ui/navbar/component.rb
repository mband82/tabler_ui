# frozen_string_literal: true

module TablerUi
  module Navbar
    # Navbar component for Tabler UI. Renders a responsive `header.navbar`
    # with left/right nav-item groups (plain links, dropdown submenus, a
    # divider, or the dark mode toggle) and a mobile collapse toggler.
    # Builder-style: the block yields the component itself, and top-level
    # items are added through the `#left`/`#right` groups' `#add` and
    # `#dropdown`.
    #
    # @example Basic usage
    #   <%= tabler_ui.navbar(brand: link_to("MyApp", root_path)) do |navbar| %>
    #     <% navbar.left do |nav| %>
    #       <% nav.add "Home", url: root_path %>
    #       <% nav.add "About", url: about_path %>
    #     <% end %>
    #   <% end %>
    #
    # @example Nested dropdown -- same item/divider/header API as the
    #   standalone TablerUi::Dropdown::Component
    #   <%= tabler_ui.navbar do |navbar| %>
    #     <% navbar.left do |nav| %>
    #       <% nav.dropdown "Admin", align: :end do |dd| %>
    #         <% dd.header "Manage" %>
    #         <% dd.item "Users", url: admin_users_path %>
    #         <% dd.divider %>
    #         <% dd.item "Settings", url: admin_settings_path, icon: "settings" %>
    #       <% end %>
    #     <% end %>
    #   <% end %>
    #
    # @example Rule 5 hooks -- component-level and per nav-item
    #   <%= tabler_ui.navbar(html: { class: "shadow-sm" },
    #                        brand_html: { class: "fw-bold" },
    #                        toggler_html: { class: "border-0" },
    #                        menu_html: { class: "gap-2" }) do |navbar| %>
    #     <% navbar.left do |nav| %>
    #       <% nav.add "Home", url: root_path, html: { class: "text-danger" } %>
    #     <% end %>
    #   <% end %>
    class Component
      include TablerUi::Base
      builder_style!

      attr_accessor :brand, :brand_autodark, :items_left, :items_right
      attr_reader :expand, :dark, :transparent, :overlap, :nav_scroll

      # @param options [Hash]
      # @option options [String]  :brand          Brand/logo markup, rendered as-is inside `.navbar-brand`
      # @option options [Boolean] :brand_autodark Adds `navbar-brand-autodark` to the brand element (default: true)
      # @option options [String, Symbol] :expand  Breakpoint at/above which the navbar shows its full menu and
      #   below which it collapses behind the toggler -- one of sm/md/lg/xl/xxl (default: "lg"). Validated via
      #   TablerUi::Breakpoint.validate!; anything else raises ArgumentError.
      # @option options [Boolean] :dark        Adds `navbar-dark`, which switches the text/brand/toggler-icon
      #   colours for a dark background. It sets no background itself -- pair it with a `bg-*` utility (e.g.
      #   via `html: { class: "bg-dark" }`).
      # @option options [Boolean] :transparent Adds `navbar-transparent` (transparent background and border).
      # @option options [Boolean] :overlap     Adds `navbar-overlap`, extending the navbar's background 9rem
      #   below it via a `:after` pseudo-element.
      # @option options [Boolean] :nav_scroll  Adds `navbar-nav-scroll` to the collapsible menu, capping it at
      #   `var(--tblr-scroll-height, 75vh)` with a scrollbar. Above the `expand:` breakpoint scrolling is
      #   switched off, so this only takes effect in the collapsed state. Set a custom cap via the menu html
      #   hook, e.g. `menu_html: { style: "--tblr-scroll-height: 300px" }`.
      # @option options [Hash] :html         Rule 5 HTML hook for the outer `header.navbar` (part :root)
      # @option options [Hash] :brand_html   Rule 5 HTML hook for `.navbar-brand` (part :brand)
      # @option options [Hash] :toggler_html Rule 5 HTML hook for the mobile toggler button (part :toggler)
      # @option options [Hash] :menu_html    Rule 5 HTML hook for the collapsible menu container (part :menu)
      def initialize(options = {})
        @brand = options[:brand]
        @brand_autodark = options.fetch(:brand_autodark, true)
        @expand = TablerUi::Breakpoint.validate!(options.fetch(:expand, "lg"), context: "navbar expand")
        @dark = options[:dark]
        @transparent = options[:transparent]
        @overlap = options[:overlap]
        @nav_scroll = options[:nav_scroll]
        @items_left = NavigationGroup.new
        @items_right = NavigationGroup.new

        initialize_html_options(options)
      end

      # Yields the left nav-item group.
      # @yield [NavigationGroup]
      def left
        yield @items_left if block_given?
      end

      # Yields the right nav-item group.
      # @yield [NavigationGroup]
      def right
        yield @items_right if block_given?
      end

      # @return [Hash] attributes for the outer `header.navbar` (part :root)
      def root_attributes
        html_for(:root, class: root_classes)
      end

      # @return [Hash] attributes for `.navbar-brand` (part :brand)
      def brand_attributes
        classes = ["navbar-brand", "me-3"]
        classes << "navbar-brand-autodark" if brand_autodark
        html_for(:brand, class: classes.join(" "))
      end

      # @return [Hash] attributes for the mobile toggler button (part :toggler)
      def toggler_attributes
        html_for(:toggler,
                 class: "navbar-toggler",
                 "data-bs-target": "#navbar-menu",
                 "aria-controls": "navbar-menu",
                 "aria-expanded": "false",
                 "aria-label": "Toggle navigation")
      end

      # @return [Hash] attributes for the collapsible menu container (part :menu)
      def menu_attributes
        html_for(:menu, class: menu_classes, id: "navbar-menu")
      end

      # @param item [NavigationGroup::Item] the item being rendered
      # @param active [Boolean] whether this item currently points at the
      #   requested page. Computed by the template via `current_page?`,
      #   since that check needs the request and isn't available here.
      # @return [Hash] attributes for this item's `li.nav-item` (part :item).
      #   Shared by every item type (link, dropdown, divider, dark mode
      #   toggle) -- like Tabs#tab_attributes / SettingsPage#item_attributes,
      #   the item's own :html (Hash or Proc taking the item) is loaded into
      #   the shared html_for storage just before resolving.
      def item_attributes(item, active: false)
        @tabler_ui_html_options[:item] = item.html
        html_for(:item, { class: item_classes(item, active) }, item)
      end

      private

      def root_classes
        classes = ["navbar", "navbar-expand-#{expand}", "d-print-none"]
        classes << "navbar-dark" if dark
        classes << "navbar-transparent" if transparent
        classes << "navbar-overlap" if overlap
        classes.join(" ")
      end

      def menu_classes
        classes = ["collapse", "navbar-collapse"]
        classes << "navbar-nav-scroll" if nav_scroll
        classes.join(" ")
      end

      def item_classes(item, active)
        classes = ["nav-item"]
        classes << "dropdown" if item.type == :dropdown
        classes << "active" if active
        classes.join(" ")
      end

      # Navigation group container for menu items (left or right side of the navbar).
      class NavigationGroup
        include Enumerable
        include TablerUi::Base

        # :html holds the caller's *raw* per-item hook (Hash or Proc taking
        # the item), not resolved attributes -- see Component#item_attributes.
        Item = Struct.new(:type, :title, :url, :target, :method, :action, :subject,
                           :active, :submenu, :align, :toggle_options, :html, keyword_init: true)

        def initialize
          @items = []
        end

        # Adds a simple navigation link.
        #
        # @param title [String] Link text
        # @param options [Hash]
        # @option options [String]  :url    Link URL
        # @option options [String]  :target Anchor target, e.g. "_blank"
        # @option options [Symbol]  :method HTTP method for a `button_to` link (e.g. :delete)
        # @option options [Object]  :action, :subject Authorization check -- `can?(action, subject)`
        #   if the view responds to `can?`, shown unconditionally otherwise
        # @option options [Boolean] :active Explicit active override. When nil (default), the
        #   template auto-detects via `current_page?(url)`.
        # @option options [Hash, #call] :html Rule 5 HTML hook for this item's `li.nav-item` (part :item)
        def add(title, options = {})
          builder_argument!(title, :title, builder: :add)

          @items << Item.new(
            type: :link,
            title: title,
            url: options[:url],
            target: options[:target],
            method: options[:method],
            action: options[:action],
            subject: options[:subject],
            active: options[:active],
            html: options[:html]
          )

          ""
        end

        # Adds a dropdown menu.
        #
        # @param title [String] Dropdown label
        # @param options [Hash]
        # @option options [Symbol, String] :align Dropdown menu alignment -- :start (default) or :end.
        #   Also tolerates the strings "start"/"end". Any other value (including the old "left"/"right")
        #   raises ArgumentError -- see TablerUi::Align.validate!.
        # @option options [Hash, #call] :html Rule 5 HTML hook for this item's `li.nav-item` (part :item)
        # @yield [DropDownProxy]
        def dropdown(title, options = {})
          builder_argument!(title, :title, builder: :dropdown)

          proxy = DropDownProxy.new
          yield proxy if block_given?

          @items << Item.new(
            type: :dropdown,
            title: title,
            submenu: proxy.items,
            align: TablerUi::Align.validate!(options[:align], context: "navbar dropdown"),
            html: options[:html]
          )

          ""
        end

        # Adds a dark mode toggle button, rendered through the real
        # `tabler_ui.dark_mode_toggle` component rather than hand-rolled markup.
        #
        # @param options [Hash]
        # @option options [Hash, #call] :html Rule 5 HTML hook for this item's `li.nav-item` (part :item)
        # @option options remaining keys forwarded to `tabler_ui.dark_mode_toggle` (e.g. :size, :title)
        def dark_mode_toggle(options = {})
          @items << Item.new(type: :dark_mode_toggle, html: options[:html], toggle_options: options.except(:html))
          ""
        end

        # Adds a divider (vertical separator).
        def divider
          @items << Item.new(type: :divider)
          ""
        end

        def each(&block)
          @items.each(&block)
        end

        def size
          @items.size
        end

        def count
          @items.count
        end

        def empty?
          @items.empty?
        end

        def [](index)
          @items[index]
        end

        def to_a
          @items
        end

        private

        # Proxy for adding dropdown items, yielded by #dropdown. Deliberately
        # the *same* builder API as the standalone TablerUi::Dropdown::Component
        # (#item / #divider / #header), so callers don't have to learn two
        # different item-adding conventions for what is visually one menu.
        class DropDownProxy
          include TablerUi::Base

          Item = Struct.new(:type, :title, :url, :target, :method, :action, :subject,
                             :icon, :disabled, :active, keyword_init: true)

          attr_reader :items

          def initialize
            @items = []
          end

          # Adds a dropdown item.
          #
          # @param title [String] Item text
          # @param options [Hash]
          # @option options [String]  :url      Item URL
          # @option options [String]  :target   Anchor target
          # @option options [Symbol]  :method   HTTP method for a `button_to` link (e.g. :delete)
          # @option options [Object]  :action, :subject Authorization check -- `can?(action, subject)`
          #   if the view responds to `can?`, shown unconditionally otherwise
          # @option options [String]  :icon     Optional Tabler icon name, rendered via tabler_ui.icon
          # @option options [Boolean] :disabled
          # @option options [Boolean] :active Explicit active override. When nil (default), the
          #   template auto-detects via `current_page?(url)`.
          def item(title, options = {})
            builder_argument!(title, :title, builder: :item)

            @items << Item.new(
              type: :item,
              title: title,
              url: options[:url],
              target: options[:target],
              method: options[:method],
              action: options[:action],
              subject: options[:subject],
              icon: options[:icon],
              disabled: options[:disabled],
              active: options[:active]
            )

            ""
          end

          # Adds a divider line between dropdown items.
          def divider
            @items << Item.new(type: :divider)
            ""
          end

          # Adds a header label between dropdown items.
          # @param title [String] Header text
          def header(title)
            builder_argument!(title, :title, builder: :header)

            @items << Item.new(type: :header, title: title)
            ""
          end
        end
      end
    end
  end
end
