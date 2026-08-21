# frozen_string_literal: true

# Ported from showcase/app/views/showcase/overlays.html.erb (overlays_3,
# overlays_4, overlays_11) -- taking each live example block as the source
# of truth, not the SNIPPETS hash, per docs/DEMOS.md.
#
# Drift found: overlays_11's SNIPPETS entry showed the body slot as the bare
# string "Sidebar content." The live block instead rendered a longer
# explanation of expand:'s width-dependent behaviour ("Below lg this behaves
# like any other offcanvas. At lg and above Bootstrap keeps it permanently
# visible and hides its header (including the close button) -- intended
# always-open-sidebar behaviour, not a bug."). The snippet's reader saw
# generic placeholder text where the live page actually explained the
# behaviour being demonstrated. Ported from the live block below.
#
# DOM id scheme: offcanvas ids are prefixed "demo-offcanvas[-...]", distinct
# from modal/toast/carousel's own "demo-<component>[-...]" prefixes, and
# unique within this file so every offcanvas demo can render together on
# /ui/demos/offcanvas without one trigger opening the wrong panel. See
# spec/lib/tabler_ui/docs/demo_ids_spec.rb.
TablerUi::Docs::DemoRegistry.define(:offcanvas) do |c|
  c.demo :end_position,
         title: "position: :end, trigger",
         source: <<~'ERB'
           <button class="btn btn-primary" data-bs-toggle="offcanvas" data-bs-target="#demo-offcanvas">
             Open filters
           </button>

           <%= tabler_ui.offcanvas "demo-offcanvas", title: "Filters", position: :end do |slots| %>
             <% slots.body { "Filter form goes here." } %>
             <% slots.footer do %>
               <%= tabler_ui.button text: "Apply", color: "primary" %>
             <% end %>
           <% end %>
         ERB

  c.demo :bottom_static,
         title: "position: :bottom, narrow, backdrop: :static",
         source: <<~'ERB'
           <button class="btn btn-outline-primary" data-bs-toggle="offcanvas" data-bs-target="#demo-offcanvas-bottom">
             Open panel
           </button>

           <%= tabler_ui.offcanvas "demo-offcanvas-bottom", title: "Details", position: :bottom,
                                   backdrop: :static do |slots| %>
             <% slots.body { "This offcanvas won't close on backdrop click." } %>
           <% end %>
         ERB

  c.demo :expand_sidebar,
         title: "expand: \"lg\" (width-dependent -- below lg a normal slide-over; at lg and above it becomes a permanently visible sidebar with its header/close button hidden, per Bootstrap)",
         source: <<~'ERB'
           <button class="btn btn-outline-primary" data-bs-toggle="offcanvas" data-bs-target="#demo-offcanvas-expand">
             Open expandable sidebar
           </button>

           <%= tabler_ui.offcanvas "demo-offcanvas-expand", title: "Sidebar", expand: "lg" do |slots| %>
             <% slots.body { "Below lg this behaves like any other offcanvas. At lg and above Bootstrap keeps it permanently visible and hides its header (including the close button) -- intended always-open-sidebar behaviour, not a bug." } %>
           <% end %>
         ERB
end
