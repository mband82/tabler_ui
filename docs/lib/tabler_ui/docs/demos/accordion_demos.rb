# frozen_string_literal: true

# Ported from showcase/app/views/showcase/layout.html.erb (the render layout:
# "showcase/example" block for "accordion - flush, toggle_style: :plus") --
# the live example block, not SNIPPETS[:layout_9], per docs/DEMOS.md. The
# live block matched its SNIPPETS entry exactly; ported from the live block
# anyway so this file is what a reader compares against, not the showcase.
TablerUi::Docs::DemoRegistry.define(:accordion) do |c|
  c.demo :flush_plus,
         title: "flush, toggle_style: :plus",
         source: <<~'ERB'
           <%= tabler_ui.accordion("demo-accordion", flush: true, toggle_style: :plus) do |acc| %>
             <% acc.item("What is Tabler UI?", open: true, icon: "info-circle") do %>
               A Rails component library on top of the Tabler.io design system.
             <% end %>
             <% acc.item("Is it free?") do %>
               Yes, MIT licensed.
             <% end %>
             <% acc.item("Does it need a database?") do %>
               No -- every component is a stateless view helper.
             <% end %>
           <% end %>
         ERB
end
