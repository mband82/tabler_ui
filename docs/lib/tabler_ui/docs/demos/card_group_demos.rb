# frozen_string_literal: true

# Ported from showcase/app/views/showcase/layout.html.erb (the render layout:
# "showcase/example" block for "card_group - cards as direct children (not
# wrapped in a column/div)") -- the live example block, not
# SNIPPETS[:layout_21], per docs/DEMOS.md.
#
# Real drift found: SNIPPETS[:layout_21] shows only two cards ("One", "Two")
# inside the group. The live block renders three ("One", "Two", "Three") --
# the snippet's reader saw code that would not have produced a group with a
# third card, and specifically undersold what card_group looks like with
# more than two children. Ported from the live block, all three cards
# included.
TablerUi::Docs::DemoRegistry.define(:card_group) do |c|
  c.demo :basics,
         title: "cards as direct children (not wrapped in a column/div)",
         source: <<~'ERB'
           <%= tabler_ui.card_group do |slots| %>
             <% slots.body do %>
               <%= tabler_ui.card title: "One" do |c| %>
                 <% c.body { "First card in the group." } %>
               <% end %>
               <%= tabler_ui.card title: "Two" do |c| %>
                 <% c.body { "Second card in the group." } %>
               <% end %>
               <%= tabler_ui.card title: "Three" do |c| %>
                 <% c.body { "Third card in the group." } %>
               <% end %>
             <% end %>
           <% end %>
         ERB
end
