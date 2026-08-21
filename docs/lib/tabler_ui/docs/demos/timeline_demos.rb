# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_18) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found: the SNIPPETS entry already matched the live block.
TablerUi::Docs::DemoRegistry.define(:timeline) do |c|
  c.demo :variants,
         title: "icons, colors, nested card content",
         source: <<~'ERB'
           <%= tabler_ui.timeline do |t| %>
             <% t.item icon: "check", color: "green" do %>
               <strong>Order placed</strong>
               <div class="text-secondary">2 hours ago</div>
             <% end %>
             <% t.item icon: "truck", color: "blue" do %>
               Shipped
             <% end %>
             <% t.item icon: "flag", color: "red" do %>
               Flagged for review
             <% end %>
           <% end %>
         ERB
end
