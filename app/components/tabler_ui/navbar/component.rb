# frozen_string_literal: true

module TablerUi
  module Navbar
    # Renders a responsive `header.navbar` with left/right nav-item groups
    # (links, dropdown submenus, a divider, or the dark mode toggle) and a
    # mobile collapse toggler. Builder-style: the block yields the component
    # itself; add items through `left`/`right`'s `add` and `dropdown`.
    #
    # @example Basic usage
    #   <%= tabler_ui.navbar(brand: link_to("MyApp", root_path)) do |navbar| %>
    #     <% navbar.left do |nav| %>
    #       <% nav.add "Home", url: root_path %>
    #       <% nav.add "About", url: about_path %>
    #     <% end %>
    #   <% end %>
    #
    # @example Nested dropdown
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
    # @example HTML attributes -- component-level and per nav-item
    #   <%= tabler_ui.navbar(html: { class: "shadow-sm" },
    #                        brand_html: { class: "fw-bold" },
    #                        toggler_html: { class: "border-0" },
    #                        menu_html: { class: "gap-2" }) do |navbar| %>
    #     <% navbar.left do |nav| %>
    #       <% nav.add "Home", url: root_path, html: { class: "text-danger" } %>
    #     <% end %>
    #   <% end %>
    #
    # @example HTML attributes -- the nav link and dropdown toggle `<a>`s themselves
    #   <%= tabler_ui.navbar(link_html: { data: { testid: "nav-link" } },
    #                        dropdown_toggle_html: { class: "fw-bold" }) do |navbar| %>
    #     <% navbar.left do |nav| %>
    #       <% nav.add "Home", url: root_path, link_html: { class: "text-danger" } %>
    #       <% nav.dropdown "Admin" do |dd| %>
    #         <% dd.item "Users", url: admin_users_path, link_html: { class: "fw-bold" } %>
    #       <% end %>
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
      # @option options [String, Symbol] :expand  Breakpoint at/above which the navbar shows its full menu;
      #   below it, collapses behind the toggler. One of `sm`/`md`/`lg`/`xl`/`xxl` (default: `lg`). Invalid
      #   values raise `ArgumentError`.
      # @option options [Boolean] :dark        Adds `navbar-dark` (switches text/brand/toggler-icon colours
      #   for a dark background). Sets no background itself -- pair with a `bg-*` utility.
      # @option options [Boolean] :transparent Adds `navbar-transparent` (transparent background and border).
      # @option options [Boolean] :overlap     Adds `navbar-overlap`, extending the navbar's background 9rem below it.
      # @option options [Boolean] :nav_scroll  Adds `navbar-nav-scroll` to the collapsible menu, capping it at
      #   `var(--tblr-scroll-height, 75vh)` with a scrollbar. Only takes effect while collapsed. Set a custom
      #   cap via `menu_html: { style: "--tblr-scroll-height: 300px" }`.
      # @option options [Hash] :html         HTML attributes for the outer `header.navbar` (part :root)
      # @option options [Hash] :brand_html   HTML attributes for `.navbar-brand` (part :brand)
      # @option options [Hash] :toggler_html HTML attributes for the mobile toggler button (part :toggler)
      # @option options [Hash] :menu_html    HTML attributes for the collapsible menu container (part :menu)
      # @option options [Hash, #call] :link_html HTML attributes applied to every plain nav
      #   link's `<a>` (or the `<button>` inside `button_to`'s `<form>` for a non-GET
      #   `method:`) -- part :link. A Hash, or a callable taking the item. Merged underneath
      #   this item's own `link_html:` given to `NavigationGroup#add`. Does *not* reach the
      #   dropdown toggle (`dropdown_toggle_html:`) or dropdown sub-item links (their own
      #   per-item `link_html:` on `DropDownProxy#item`).
      # @option options [Hash, #call] :dropdown_toggle_html HTML attributes applied to every
      #   dropdown's toggle `<a class="dropdown-toggle">` (part :dropdown_toggle) -- a Hash,
      #   or a callable taking the item. A caller's own `data:` deep-merges with the toggle's
      #   built-in `data-bs-toggle`/`data-controller` rather than replacing them.
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
      # @param options [Hash]
      # @option options [Object] :auth Authorization value (CLAUDE.md rule 8) for
      #   this group's items -- checked against the globally configured auth_method.
      #   Defaults to the navbar's own :auth when omitted; items added inside the
      #   block (NavigationGroup#add / #dropdown / #dark_mode_toggle / #divider)
      #   inherit this as their own default in turn.
      # @yield [NavigationGroup]
      def left(options = {})
        @items_left.auth = options.key?(:auth) ? options[:auth] : auth
        yield @items_left if block_given?
      end

      # Yields the right nav-item group.
      # @param options [Hash]
      # @option options [Object] :auth Authorization value (CLAUDE.md rule 8) for
      #   this group's items -- see #left.
      # @yield [NavigationGroup]
      def right(options = {})
        @items_right.auth = options.key?(:auth) ? options[:auth] : auth
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

      # @param item [NavigationGroup::Item] a :link item
      # @param active [Boolean] whether this item currently points at the
      #   requested page -- see #item_attributes
      # @return [Hash] attributes for this item's nav link (part :link) --
      #   the `<a>` rendered via `link_to`, or the html_options Hash handed
      #   to `button_to` for a non-GET `method:` (merged with `method:`
      #   itself by the caller, following `button#root_attributes`'
      #   precedent). Merges, in order: this method's own defaults
      #   (class, target), the component-level `link_html:` option (a Hash,
      #   or a callable taking the item), then this item's own `link_html:`
      #   (set via NavigationGroup#add) -- same three-layer precedent as
      #   Pagination#item_attributes.
      def link_attributes(item, active: false)
        defaults = { class: link_classes(active), target: item.target }

        TablerUi::HtmlOptions.merge_html(html_for(:link, defaults, item), resolve(item.link_html, item))
      end

      # @param item [NavigationGroup::Item] a :dropdown item
      # @return [Hash] attributes for the dropdown toggle `<a>` (part
      #   :dropdown_toggle). `data-bs-toggle`/`data-controller` are baked
      #   into the defaults (not spread separately in the ERB) so a caller's
      #   own `data:` on `dropdown_toggle_html:` deep-merges with them via
      #   `merge_html` instead of clobbering them.
      def dropdown_toggle_attributes(item)
        defaults = {
          class: "nav-link dropdown-toggle",
          href: "#",
          data: { "bs-toggle": "dropdown", controller: "tabler-ui--dropdown-menu" },
          role: "button",
          "aria-expanded": "false"
        }

        html_for(:dropdown_toggle, defaults, item)
      end

      # @param item [NavigationGroup::DropDownProxy::Item] a dropdown
      #   sub-item (type :item)
      # @param active [Boolean] whether this item currently points at the
      #   requested page -- see #item_attributes
      # @return [Hash] attributes for this sub-item's link -- the `<a>`
      #   rendered via `link_to`, or the html_options Hash handed to
      #   `button_to` for a non-GET `method:`. There is no component-level
      #   hook for this part (only #link_attributes' `link_html:` reaches
      #   the *top-level* nav link) -- just this sub-item's own `link_html:`
      #   (set via `DropDownProxy#item`), merged over the defaults.
      def dropdown_item_link_attributes(item, active: false)
        defaults = { class: dropdown_item_classes(item, active), target: item.target, disabled: item.disabled }

        TablerUi::HtmlOptions.merge_html(defaults, resolve(item.link_html, item))
      end

      private

      # @param hook [Hash, #call, nil] a raw rule-5 hook value
      # @param item [NavigationGroup::Item, NavigationGroup::DropDownProxy::Item]
      #   passed to +hook+ when it's callable
      # @return [Hash] the hook resolved to a plain Hash, ready for merge_html
      def resolve(hook, item)
        hook.respond_to?(:call) ? hook.call(item) : hook
      end

      def link_classes(active)
        classes = ["nav-link"]
        classes << "active" if active
        classes.join(" ")
      end

      def dropdown_item_classes(item, active)
        classes = ["dropdown-item"]
        classes << "active" if active
        classes << "disabled" if item.disabled
        classes.join(" ")
      end

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
        # :link_html is the same kind of raw hook, for the nav link itself
        # rather than its `<li>` -- see Component#link_attributes. :auth is
        # the item's resolved (post-inheritance) `auth:` value (CLAUDE.md
        # rule 8) -- stored for completeness, though only authorized items
        # ever make it into @items in the first place.
        Item = Struct.new(:type, :title, :url, :target, :method, :action, :subject,
                           :active, :submenu, :align, :toggle_options, :html, :link_html, :auth, keyword_init: true)

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
        # @option options [Hash, #call] :html HTML attributes for this item's `li.nav-item` (part :item)
        # @option options [Hash, #call] :link_html HTML attributes for this item's nav link
        #   itself (part :link) -- the `<a>`, or the `<button>` inside `button_to`'s `<form>`
        #   for a non-GET `method:`. Merged on top of the component-level `link_html:` option
        #   -- see Component#link_attributes.
        # @option options [Object] :auth Per-item authorization value (CLAUDE.md rule 8)
        #   -- checked against the globally configured auth_method. Defaults to this
        #   group's own :auth (see Component#left / #right) when omitted. An
        #   unauthorized item is not appended. Unrelated to :action/:subject above.
        # @return [String, nil] empty string, to avoid stray output in a capture
        #   context; nil (no-op) if :auth denied it
        def add(title, options = {})
          effective_auth = options.key?(:auth) ? options[:auth] : auth
          return unless TablerUi::Authorization.authorized?(effective_auth)

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
            html: options[:html],
            link_html: options[:link_html],
            auth: effective_auth
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
        # @option options [Hash, #call] :html HTML attributes for this item's `li.nav-item` (part :item)
        # @option options [Object] :auth Per-item authorization value (CLAUDE.md rule 8) for
        #   the dropdown item itself -- checked against the globally configured auth_method.
        #   Defaults to this group's own :auth (see Component#left / #right) when omitted. An
        #   unauthorized dropdown is not appended, and its block never runs (its items are
        #   never built). This resolved value is also the default that everything added
        #   inside the block (DropDownProxy#item / #divider / #header) inherits, one level
        #   deeper than the group's own inheritance.
        # @yield [DropDownProxy]
        # @return [String, nil] empty string, to avoid stray output in a capture
        #   context; nil (no-op) if :auth denied it
        def dropdown(title, options = {})
          effective_auth = options.key?(:auth) ? options[:auth] : auth
          return unless TablerUi::Authorization.authorized?(effective_auth)

          builder_argument!(title, :title, builder: :dropdown)

          proxy = DropDownProxy.new
          proxy.auth = effective_auth
          yield proxy if block_given?

          @items << Item.new(
            type: :dropdown,
            title: title,
            submenu: proxy.items,
            align: TablerUi::Align.validate!(options[:align], context: "navbar dropdown"),
            html: options[:html],
            auth: effective_auth
          )

          ""
        end

        # Adds a dark mode toggle button, rendered through the real
        # `tabler_ui.dark_mode_toggle` component rather than hand-rolled markup.
        #
        # @param options [Hash]
        # @option options [Hash, #call] :html HTML attributes for this item's `li.nav-item` (part :item)
        # @option options [Object] :auth Per-item authorization value (CLAUDE.md rule 8)
        #   -- defaults to this group's own :auth (see Component#left / #right) when
        #   omitted. Not forwarded to the inner `tabler_ui.dark_mode_toggle` call, which
        #   has its own independent :auth gating via the dispatcher.
        # @option options remaining keys forwarded to `tabler_ui.dark_mode_toggle` (e.g. :size, :title)
        # @return [String, nil] empty string, to avoid stray output in a capture
        #   context; nil (no-op) if :auth denied it
        def dark_mode_toggle(options = {})
          effective_auth = options.key?(:auth) ? options[:auth] : auth
          return unless TablerUi::Authorization.authorized?(effective_auth)

          @items << Item.new(type: :dark_mode_toggle, html: options[:html],
                              toggle_options: options.except(:html, :auth), auth: effective_auth)
          ""
        end

        # Adds a divider (vertical separator).
        # @param options [Hash]
        # @option options [Object] :auth Per-item authorization value (CLAUDE.md rule 8)
        #   -- defaults to this group's own :auth (see Component#left / #right) when omitted.
        # @return [String, nil] empty string, to avoid stray output in a capture
        #   context; nil (no-op) if :auth denied it
        def divider(options = {})
          effective_auth = options.key?(:auth) ? options[:auth] : auth
          return unless TablerUi::Authorization.authorized?(effective_auth)

          @items << Item.new(type: :divider, auth: effective_auth)
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

          # :link_html holds the caller's *raw* per-item hook (Hash or Proc
          # taking the item), not resolved attributes -- see
          # Component#dropdown_item_link_attributes. :auth is the item's
          # resolved (post-inheritance) `auth:` value (CLAUDE.md rule 8) --
          # stored for completeness, though only authorized items ever make
          # it into @items in the first place.
          Item = Struct.new(:type, :title, :url, :target, :method, :action, :subject,
                             :icon, :disabled, :active, :link_html, :auth, keyword_init: true)

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
          # @option options [Hash, #call] :link_html HTML attributes for this sub-item's link
          #   itself (not routed through a component-level option -- see
          #   Component#dropdown_item_link_attributes) -- the `<a>`, or the `<button>` inside
          #   `button_to`'s `<form>` for a non-GET `method:`.
          # @option options [Object] :auth Per-item authorization value (CLAUDE.md rule 8)
          #   -- checked against the globally configured auth_method. Defaults to this
          #   dropdown's own :auth (its resolved value from NavigationGroup#dropdown) when
          #   omitted. An unauthorized item is not appended.
          # @return [String, nil] empty string, to avoid stray output in a capture
          #   context; nil (no-op) if :auth denied it
          def item(title, options = {})
            effective_auth = options.key?(:auth) ? options[:auth] : auth
            return unless TablerUi::Authorization.authorized?(effective_auth)

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
              active: options[:active],
              link_html: options[:link_html],
              auth: effective_auth
            )

            ""
          end

          # Adds a divider line between dropdown items.
          # @param options [Hash]
          # @option options [Object] :auth Per-item authorization value (CLAUDE.md rule 8)
          #   -- defaults to this dropdown's own :auth when omitted.
          # @return [String, nil] empty string, to avoid stray output in a capture
          #   context; nil (no-op) if :auth denied it
          def divider(options = {})
            effective_auth = options.key?(:auth) ? options[:auth] : auth
            return unless TablerUi::Authorization.authorized?(effective_auth)

            @items << Item.new(type: :divider, auth: effective_auth)
            ""
          end

          # Adds a header label between dropdown items.
          # @param title [String] Header text
          # @param options [Hash]
          # @option options [Object] :auth Per-item authorization value (CLAUDE.md rule 8)
          #   -- defaults to this dropdown's own :auth when omitted.
          # @return [String, nil] empty string, to avoid stray output in a capture
          #   context; nil (no-op) if :auth denied it
          def header(title, options = {})
            effective_auth = options.key?(:auth) ? options[:auth] : auth
            return unless TablerUi::Authorization.authorized?(effective_auth)

            builder_argument!(title, :title, builder: :header)

            @items << Item.new(type: :header, title: title, auth: effective_auth)
            ""
          end
        end
      end
    end
  end
end
