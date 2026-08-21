# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_15) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found: the SNIPPETS entry already matched the live block.
TablerUi::Docs::DemoRegistry.define(:dimmer) do |c|
  c.demo :active,
         title: "active loading overlay",
         source: <<~'ERB'
           <%= tabler_ui.dimmer active: true do |slots| %>
             <% slots.content do %>
               <div class="p-4">Table rows would render here.</div>
             <% end %>
           <% end %>
         ERB
end
