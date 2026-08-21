# frozen_string_literal: true

# Ported from showcase/app/views/showcase/overlays.html.erb (overlays_7,
# overlays_12 through overlays_19) -- taking each live example block as the
# source of truth, not the SNIPPETS hash, per docs/DEMOS.md. No drift found
# for any of these nine; SNIPPETS matched the live blocks in every case.
#
# No DOM ids: dropdown is self-triggering -- Bootstrap's dropdown JS wires
# up directly on the toggle element itself (data-bs-toggle="dropdown"), with
# no data-bs-target id to collide with another demo's. See
# spec/lib/tabler_ui/docs/demo_ids_spec.rb, which still asserts this file's
# demos carry no duplicate ids (there are none to begin with, but the
# guarantee is proved rather than assumed).
TablerUi::Docs::DemoRegistry.define(:dropdown) do |c|
  c.demo :basic,
         title: "color, align: :end, self-triggering",
         source: <<~'ERB'
           <%= tabler_ui.dropdown(label: "Actions", color: "secondary", align: :end) do |dropdown| %>
             <% dropdown.item("Edit", url: "#", icon: "pencil") %>
             <% dropdown.item("Duplicate", url: "#", icon: "copy") %>
             <% dropdown.divider %>
             <% dropdown.item("Delete", url: "#", icon: "trash") %>
           <% end %>
         ERB

  c.demo :dark,
         title: "dark: true",
         source: <<~'ERB'
           <%= tabler_ui.dropdown(label: "Actions", dark: true) do |dropdown| %>
             <% dropdown.item("Edit", url: "#", icon: "pencil") %>
             <% dropdown.item("Duplicate", url: "#", icon: "copy") %>
             <% dropdown.divider %>
             <% dropdown.item("Delete", url: "#", icon: "trash") %>
           <% end %>
         ERB

  c.demo :scrollable,
         title: "scrollable: true (caps the menu at 13rem and scrolls)",
         source: <<~'ERB'
           <%= tabler_ui.dropdown(label: "Choose", scrollable: true) do |dropdown| %>
             <% (1..12).each do |n| %>
               <% dropdown.item("Item #{n}", url: "#") %>
             <% end %>
           <% end %>
         ERB

  c.demo :arrow,
         title: "arrow: true",
         source: <<~'ERB'
           <%= tabler_ui.dropdown(label: "Actions", arrow: true) do |dropdown| %>
             <% dropdown.item("Edit", url: "#", icon: "pencil") %>
             <% dropdown.item("Delete", url: "#", icon: "trash") %>
           <% end %>
         ERB

  c.demo :arrow_end,
         title: "arrow: true, align: :end",
         source: <<~'ERB'
           <%= tabler_ui.dropdown(label: "Actions", arrow: true, align: :end) do |dropdown| %>
             <% dropdown.item("Edit", url: "#", icon: "pencil") %>
             <% dropdown.item("Delete", url: "#", icon: "trash") %>
           <% end %>
         ERB

  c.demo :direction_end,
         title: "direction: \"end\"",
         source: <<~'ERB'
           <%= tabler_ui.dropdown(label: "Actions", direction: "end") do |dropdown| %>
             <% dropdown.item("Edit", url: "#", icon: "pencil") %>
             <% dropdown.item("Delete", url: "#", icon: "trash") %>
           <% end %>
         ERB

  c.demo :direction_start,
         title: "direction: \"start\"",
         source: <<~'ERB'
           <%= tabler_ui.dropdown(label: "Actions", direction: "start") do |dropdown| %>
             <% dropdown.item("Edit", url: "#", icon: "pencil") %>
             <% dropdown.item("Delete", url: "#", icon: "trash") %>
           <% end %>
         ERB

  c.demo :direction_up,
         title: "direction: \"up\" (placed here so the menu has room above it)",
         source: <<~'ERB'
           <%= tabler_ui.dropdown(label: "Actions", direction: "up") do |dropdown| %>
             <% dropdown.item("Edit", url: "#", icon: "pencil") %>
             <% dropdown.item("Delete", url: "#", icon: "trash") %>
           <% end %>
         ERB

  c.demo :align_breakpoint,
         title: "align: :end, align_breakpoint: \"md\" (responsive alignment class -- effect only visible once the window crosses the md breakpoint)",
         source: <<~'ERB'
           <%= tabler_ui.dropdown(label: "Actions", align: :end, align_breakpoint: "md") do |dropdown| %>
             <% dropdown.item("Edit", url: "#", icon: "pencil") %>
             <% dropdown.item("Delete", url: "#", icon: "trash") %>
           <% end %>
         ERB
end
