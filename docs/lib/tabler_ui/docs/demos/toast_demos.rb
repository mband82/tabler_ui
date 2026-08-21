# frozen_string_literal: true

# Ported from showcase/app/views/showcase/overlays.html.erb (overlays_5,
# overlays_6) -- taking each live example block as the source of truth, not
# the SNIPPETS hash, per docs/DEMOS.md. No drift found for these two;
# SNIPPETS matched the live blocks in both cases.
#
# DOM id scheme: toast ids are prefixed "demo-toast[-...]", distinct from
# modal/offcanvas/carousel's own "demo-<component>[-...]" prefixes, and
# unique within this file so every toast demo can render together on
# /ui/demos/toast without one trigger showing the wrong toast. See
# spec/lib/tabler_ui/docs/demo_ids_spec.rb.
TablerUi::Docs::DemoRegistry.define(:toast) do |c|
  c.demo :success,
         title: "color, trigger via html: { id: }",
         source: <<~'ERB'
           <button class="btn btn-success" data-bs-toggle="toast" data-bs-target="#demo-toast">
             Show toast
           </button>

           <div class="toast-container position-fixed bottom-0 end-0 p-3">
             <%= tabler_ui.toast title: "Success", color: "success", html: { id: "demo-toast" } do |slots| %>
               <% slots.body { "Changes saved." } %>
             <% end %>
           </div>
         ERB

  c.demo :sticky_warning,
         title: "position:, autohide: false, delay:",
         source: <<~'ERB'
           <button class="btn btn-outline-warning" data-bs-toggle="toast" data-bs-target="#demo-toast-warning">
             Show sticky warning
           </button>

           <%= tabler_ui.toast title: "Heads up", color: "warning", autohide: false,
                               position: "top-right", html: { id: "demo-toast-warning" } do |slots| %>
             <% slots.body { "This toast stays until dismissed." } %>
           <% end %>
         ERB
end
