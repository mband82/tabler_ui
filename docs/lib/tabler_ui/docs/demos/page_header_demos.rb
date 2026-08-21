# frozen_string_literal: true

# Ported from showcase/app/views/showcase/layout.html.erb (the render layout:
# "showcase/example" blocks for "page_header", "page_header - border: true",
# "page_header - title_size: \"lg\"", and "page_header - pretitle:/subtitle:")
# -- the live example blocks, not SNIPPETS[:layout_2]/[:layout_15..17], per
# docs/DEMOS.md. All four live blocks matched their SNIPPETS entries exactly;
# ported from the live block anyway so this file is what a reader compares
# against, not the showcase.
TablerUi::Docs::DemoRegistry.define(:page_header) do |c|
  c.demo :basics,
         title: "title, pretitle, buttons slot",
         source: <<~'ERB'
           <%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview" do |slots| %>
             <% slots.buttons do %>
               <%= tabler_ui.button text: "New report", color: "primary", icon: "plus" %>
             <% end %>
           <% end %>
         ERB

  c.demo :border,
         title: "border: true",
         source: <<~'ERB'
           <%= tabler_ui.page_header title: "Dashboard", border: true %>
         ERB

  c.demo :title_size,
         title: "title_size: \"lg\"",
         source: <<~'ERB'
           <%= tabler_ui.page_header title: "Dashboard", title_size: "lg" %>
         ERB

  c.demo :subtitle,
         title: "pretitle: (above title) + subtitle: (below title)",
         source: <<~'ERB'
           <%= tabler_ui.page_header title: "Dashboard", pretitle: "Overview", subtitle: "Last 30 days" %>
         ERB
end
