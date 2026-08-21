# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_26) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. `badge_list`
# is its own component (separate from `badge`), so it gets its own file even
# though the old showcase put it on the same page. No drift found: the
# SNIPPETS entry already matched the live block.
TablerUi::Docs::DemoRegistry.define(:badge_list) do |c|
  c.demo :body,
         title: "wraps several badges in a flex .badges-list container",
         source: <<~'ERB'
           <%= tabler_ui.badge_list do |slots| %>
             <% slots.body do %>
               <%= tabler_ui.badge text: "New" %>
               <%= tabler_ui.badge text: "Hot" %>
             <% end %>
           <% end %>
         ERB
end
