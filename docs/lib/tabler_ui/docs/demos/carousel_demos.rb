# frozen_string_literal: true

# Ported from showcase/app/views/showcase/overlays.html.erb (overlays_8,
# overlays_20) -- taking each live example block as the source of truth, not
# the SNIPPETS hash, per docs/DEMOS.md.
#
# Drift found: overlays_20's SNIPPETS entry showed only two carousel.item
# calls (Snow, Desert). The live block rendered three (Snow, Desert, Beach)
# -- the snippet silently dropped the third slide. Ported from the live
# block, all three items included.
#
# DOM id scheme: carousel ids are prefixed "demo-carousel[-...]", distinct
# from modal/offcanvas/toast's own "demo-<component>[-...]" prefixes, and
# unique within this file so every carousel demo can render together on
# /ui/demos/carousel without one instance's Bootstrap.Carousel controller
# picking up another's slides. See spec/lib/tabler_ui/docs/demo_ids_spec.rb.
TablerUi::Docs::DemoRegistry.define(:carousel) do |c|
  c.demo :captions,
         title: "captions, indicators: :thumb",
         source: <<~'ERB'
           <%= tabler_ui.carousel("demo-carousel", indicators: :thumb) do |carousel| %>
             <% carousel.item(image: "https://picsum.photos/id/1015/900/300", caption: "Mountains",
                              caption_background: true, active: true) %>
             <% carousel.item(image: "https://picsum.photos/id/1016/900/300", caption: "Canyon",
                              caption_background: true) %>
             <% carousel.item(image: "https://picsum.photos/id/1018/900/300", caption: "River",
                              caption_background: true) %>
           <% end %>
         ERB

  c.demo :dark,
         title: "dark: true (dark indicators, captions and control icons, for use over light images)",
         source: <<~'ERB'
           <%= tabler_ui.carousel("demo-carousel-dark", dark: true, indicators: :thumb) do |carousel| %>
             <% carousel.item(image: "https://picsum.photos/id/1039/900/300", caption: "Snow",
                              caption_background: true, active: true) %>
             <% carousel.item(image: "https://picsum.photos/id/1043/900/300", caption: "Desert",
                              caption_background: true) %>
             <% carousel.item(image: "https://picsum.photos/id/1044/900/300", caption: "Beach",
                              caption_background: true) %>
           <% end %>
         ERB
end
