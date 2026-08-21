# frozen_string_literal: true

# Ported from showcase/app/views/showcase/layout.html.erb (the render layout:
# "showcase/example" block for "settings_page") -- the live example block,
# not SNIPPETS[:layout_8], per docs/DEMOS.md. The live block matched its
# SNIPPETS entry exactly; ported from the live block anyway so this file is
# what a reader compares against, not the showcase.
TablerUi::Docs::DemoRegistry.define(:settings_page) do |c|
  c.demo :basics,
         title: "item blocks with icons",
         source: <<~'ERB'
           <%= tabler_ui.settings_page("demo-settings", title: "Settings") do |sp| %>
             <% sp.item("General", icon: "settings") do %>
               General settings content.
             <% end %>
             <% sp.item("Security", icon: "shield-check") do %>
               Security settings content.
             <% end %>
             <% sp.item("Notifications", icon: "bell") do %>
               Notification settings content.
             <% end %>
           <% end %>
         ERB
end
