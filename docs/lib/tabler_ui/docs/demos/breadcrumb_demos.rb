# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_20) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found: the SNIPPETS entry already matched the live block.
TablerUi::Docs::DemoRegistry.define(:breadcrumb) do |c|
  c.demo :arrows,
         title: "style: :arrows, muted",
         source: <<~'ERB'
           <%= tabler_ui.breadcrumb(style: :arrows, muted: true) do |breadcrumb| %>
             <% breadcrumb.item("Home", url: "#") %>
             <% breadcrumb.item("Library", url: "#") %>
             <% breadcrumb.item("Data") %>
           <% end %>
         ERB
end
