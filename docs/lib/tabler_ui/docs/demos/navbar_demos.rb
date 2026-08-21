# frozen_string_literal: true

# Ported from showcase/app/views/showcase/layout.html.erb (the render layout:
# "showcase/example" blocks for "navbar", "navbar - expand: \"sm\"", "navbar -
# dark: true", "navbar - transparent: true", "navbar - overlap: true", and
# "navbar - nav_scroll: true") -- the live example blocks, not the
# SNIPPETS[:layout_1]/[:layout_10..14] entries, per docs/DEMOS.md. All six
# live blocks matched their SNIPPETS entries exactly; ported from the live
# block anyway so this file is what a reader compares against, not the
# showcase.
#
# Two deliberate adaptations, neither a drift from the showcase -- both are
# things the showcase never had to deal with because it only ever rendered
# one navbar demo per page:
#
# 1. Every `nav.add`/`dd.item` below that lacked an explicit `active:` in the
#    live block now carries `active: false`.
#    app/components/tabler_ui/navbar/_nav_item.html.erb falls back to
#    `current_page?(entry.url)` whenever `active:` is nil, and `current_page?`
#    raises without a `request` object -- present in a real controller render
#    (the showcase, any host app) but absent from the bare ActionView context
#    spec/lib/tabler_ui/docs/demo_registry_spec.rb renders every demo
#    through. Spelling out `active:` sidesteps that harness gap and arguably
#    documents the API better: a reader copying the demo sees the explicit
#    active-state option instead of relying on implicit route matching that
#    only works inside a real request. "Home" already carried `active: true`
#    in the live block and is unchanged.
# 2. Every demo below sets its own `menu_html: { id: ... }` plus a matching
#    `toggler_html: { "data-bs-target": "#...", "aria-controls": ... }`.
#    app/components/tabler_ui/navbar/component.rb#menu_attributes hardcodes
#    `id: "navbar-menu"` (and #toggler_attributes hardcodes
#    `data-bs-target`/`aria-controls` to match) -- fine for one navbar per
#    page, but spec/lib/tabler_ui/docs/demo_ids_spec.rb renders every
#    registered demo for a component on one page and asserts no id=
#    repeats, exactly what /ui/demos/navbar itself does. Six demos each
#    defaulting to id="navbar-menu" would collide there, so each one is
#    given its own id here -- both halves (menu + toggler) are overridden
#    together since the toggler's `data-bs-target`/`aria-controls` must
#    keep pointing at whichever id its own menu actually has.
TablerUi::Docs::DemoRegistry.define(:navbar) do |c|
  c.demo :basics,
         title: "left/right nav items, dropdown, dark mode toggle",
         source: <<~'ERB'
           <%= tabler_ui.navbar(brand: link_to("MyApp", "#"),
                                 menu_html: { id: "navbar-basics-menu" },
                                 toggler_html: { "data-bs-target": "#navbar-basics-menu", "aria-controls": "navbar-basics-menu" }) do |navbar| %>
             <% navbar.left do |nav| %>
               <% nav.add "Home", url: "#", active: true %>
               <% nav.add "Reports", url: "#", active: false %>
               <% nav.dropdown "Admin", align: :end do |dd| %>
                 <% dd.header "Manage" %>
                 <% dd.item "Users", url: "#", icon: "users", active: false %>
                 <% dd.divider %>
                 <% dd.item "Settings", url: "#", icon: "settings", active: false %>
               <% end %>
             <% end %>
             <% navbar.right do |nav| %>
               <% nav.dark_mode_toggle %>
             <% end %>
           <% end %>
         ERB

  c.demo :expand_sm,
         title: "expand: \"sm\" (collapses above sm, instead of the lg default)",
         source: <<~'ERB'
           <%= tabler_ui.navbar(brand: link_to("MyApp", "#"), expand: "sm",
                                 menu_html: { id: "navbar-expand-sm-menu" },
                                 toggler_html: { "data-bs-target": "#navbar-expand-sm-menu", "aria-controls": "navbar-expand-sm-menu" }) do |navbar| %>
             <% navbar.left do |nav| %>
               <% nav.add "Home", url: "#", active: true %>
               <% nav.add "Reports", url: "#", active: false %>
             <% end %>
           <% end %>
         ERB

  c.demo :dark,
         title: "dark: true (text/icons only -- paired with bg-primary via html:)",
         source: <<~'ERB'
           <%= tabler_ui.navbar(brand: link_to("MyApp", "#"), dark: true, html: { class: "bg-primary" },
                                 menu_html: { id: "navbar-dark-menu" },
                                 toggler_html: { "data-bs-target": "#navbar-dark-menu", "aria-controls": "navbar-dark-menu" }) do |navbar| %>
             <% navbar.left do |nav| %>
               <% nav.add "Home", url: "#", active: true %>
               <% nav.add "Reports", url: "#", active: false %>
             <% end %>
           <% end %>
         ERB

  c.demo :transparent,
         title: "transparent: true",
         source: <<~'ERB'
           <div class="bg-blue-lt p-3">
             <%= tabler_ui.navbar(brand: link_to("MyApp", "#"), transparent: true,
                                   menu_html: { id: "navbar-transparent-menu" },
                                   toggler_html: { "data-bs-target": "#navbar-transparent-menu", "aria-controls": "navbar-transparent-menu" }) do |navbar| %>
               <% navbar.left do |nav| %>
                 <% nav.add "Home", url: "#", active: true %>
                 <% nav.add "Reports", url: "#", active: false %>
               <% end %>
             <% end %>
           </div>
         ERB

  c.demo :overlap,
         title: "overlap: true (background extends 9rem below it; content sits on top)",
         source: <<~'ERB'
           <%= tabler_ui.navbar(brand: link_to("MyApp", "#"), overlap: true,
                                 menu_html: { id: "navbar-overlap-menu" },
                                 toggler_html: { "data-bs-target": "#navbar-overlap-menu", "aria-controls": "navbar-overlap-menu" }) do |navbar| %>
             <% navbar.left do |nav| %>
               <% nav.add "Home", url: "#", active: true %>
             <% end %>
           <% end %>
           <div class="container-xl mt-n5">
             <div class="card">
               <div class="card-body">This card overlaps the navbar's extended background.</div>
             </div>
           </div>
         ERB

  c.demo :nav_scroll,
         title: "nav_scroll: true, menu_html: custom --tblr-scroll-height (collapse below lg to see it scroll)",
         source: <<~'ERB'
           <%= tabler_ui.navbar(brand: link_to("MyApp", "#"), nav_scroll: true,
                                 menu_html: { id: "navbar-nav-scroll-menu", style: "--tblr-scroll-height: 300px" },
                                 toggler_html: { "data-bs-target": "#navbar-nav-scroll-menu", "aria-controls": "navbar-nav-scroll-menu" }) do |navbar| %>
             <% navbar.left do |nav| %>
               <% (1..10).each do |n| %>
                 <% nav.add "Item #{n}", url: "#", active: false %>
               <% end %>
             <% end %>
           <% end %>
         ERB
end
