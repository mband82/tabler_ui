# frozen_string_literal: true

# Ported from showcase/app/views/showcase/layout.html.erb (the render layout:
# "showcase/example" blocks for "card - title + body + footer", "card -
# status strip, borderless, stacked", "card - status_position: \"top\"",
# "\"start\"" and "\"bottom\"") -- the live example blocks, not
# SNIPPETS[:layout_3]/[:layout_4]/[:layout_18..20], per docs/DEMOS.md. All
# five live blocks matched their SNIPPETS entries exactly; ported from the
# live block anyway so this file is what a reader compares against, not the
# showcase. The two-column/three-column row wrappers the showcase used to
# lay these out side by side are dropped -- that's showcase page layout, not
# part of what each demo renders.
TablerUi::Docs::DemoRegistry.define(:card) do |c|
  c.demo :basics,
         title: "title + body + footer",
         source: <<~'ERB'
           <%= tabler_ui.card title: "Card title" do |slots| %>
             <% slots.body { "Card body content." } %>
             <% slots.footer { "Updated 3 min ago" } %>
           <% end %>
         ERB

  c.demo :status_stacked,
         title: "status strip, borderless, stacked",
         source: <<~'ERB'
           <%= tabler_ui.card title: "Server status", status: "danger", stacked: true do |slots| %>
             <% slots.body { "3 servers are unreachable." } %>
           <% end %>
         ERB

  c.demo :status_top,
         title: "status_position: \"top\" (default)",
         source: <<~'ERB'
           <%= tabler_ui.card title: "Top strip", status: "danger", status_position: "top" do |slots| %>
             <% slots.body { "Status strip along the top edge." } %>
           <% end %>
         ERB

  c.demo :status_start,
         title: "status_position: \"start\"",
         source: <<~'ERB'
           <%= tabler_ui.card title: "Start strip", status: "azure", status_position: "start" do |slots| %>
             <% slots.body { "Status strip along the leading edge." } %>
           <% end %>
         ERB

  c.demo :status_bottom,
         title: "status_position: \"bottom\"",
         source: <<~'ERB'
           <%= tabler_ui.card title: "Bottom strip", status: "success", status_position: "bottom" do |slots| %>
             <% slots.body { "Status strip along the bottom edge." } %>
           <% end %>
         ERB
end
