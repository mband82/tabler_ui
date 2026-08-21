# frozen_string_literal: true

# Ported from showcase/app/views/showcase/overlays.html.erb (overlays_1,
# overlays_2, overlays_9, overlays_10) -- taking each live example block as
# the source of truth, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found for these four; SNIPPETS matched the live blocks in every case.
#
# DOM id scheme: modal ids are prefixed "demo-modal[-...]" so they cannot
# collide with another component's demo ids (offcanvas/toast/carousel use
# their own "demo-<component>[-...]" prefixes), and each modal demo's id is
# unique within this file so every modal demo can render together on
# /ui/demos/modal without one trigger opening the wrong dialog. See
# spec/lib/tabler_ui/docs/demo_ids_spec.rb.
TablerUi::Docs::DemoRegistry.define(:modal) do |c|
  c.demo :basic,
         title: "title, body/footer slots, trigger",
         source: <<~'ERB'
           <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#demo-modal">
             Open modal
           </button>

           <%= tabler_ui.modal "demo-modal", title: "Confirm" do |slots| %>
             <% slots.body { "Are you sure you want to continue?" } %>
             <% slots.footer do %>
               <button class="btn btn-link link-secondary" data-bs-dismiss="modal">Cancel</button>
               <%= tabler_ui.button text: "Yes, continue", color: "primary" %>
             <% end %>
           <% end %>
         ERB

  c.demo :danger,
         title: "size: lg, centered, blur, status strip",
         source: <<~'ERB'
           <button class="btn btn-outline-danger" data-bs-toggle="modal" data-bs-target="#demo-modal-danger">
             Delete item
           </button>

           <%= tabler_ui.modal "demo-modal-danger", title: "Delete item", size: "lg",
                               centered: true, blur: true, status: "danger" do |slots| %>
             <% slots.body { "This action cannot be undone." } %>
           <% end %>
         ERB

  c.demo :full_width,
         title: "full_width: true (spans the viewport; raises if combined with size:)",
         source: <<~'ERB'
           <button class="btn btn-outline-primary" data-bs-toggle="modal" data-bs-target="#demo-modal-full-width">
             Open full-width modal
           </button>

           <%= tabler_ui.modal "demo-modal-full-width", title: "Full width", full_width: true do |slots| %>
             <% slots.body { "This dialog fills the viewport width with a small margin instead of a fixed max-width." } %>
           <% end %>
         ERB

  c.demo :fullscreen_md_down,
         title: "size: \"fullscreen-md-down\" (width-dependent -- resize the window to see it flip)",
         source: <<~'ERB'
           <button class="btn btn-outline-primary" data-bs-toggle="modal" data-bs-target="#demo-modal-fullscreen-md">
             Open responsive fullscreen modal
           </button>

           <%= tabler_ui.modal "demo-modal-fullscreen-md", title: "Responsive fullscreen", size: "fullscreen-md-down" do |slots| %>
             <% slots.body { "Below the md breakpoint this fills the screen; at md and above it's a normal dialog." } %>
           <% end %>
         ERB
end
