# frozen_string_literal: true

# Ported from showcase/app/views/showcase/layout.html.erb (the render layout:
# "showcase/example" block for "datagrid") -- the live example block, not
# SNIPPETS[:layout_6], per docs/DEMOS.md. The live block matched its
# SNIPPETS entry exactly; ported from the live block anyway so this file is
# what a reader compares against, not the showcase.
TablerUi::Docs::DemoRegistry.define(:datagrid) do |c|
  c.demo :basics,
         title: "content: and a block item",
         source: <<~'ERB'
           <%= tabler_ui.datagrid do |dg| %>
             <% dg.item "Full name", content: "Ada Lovelace" %>
             <% dg.item "Email", content: "ada@example.com" %>
             <% dg.item "Bio" do %>
               <strong>Mathematician</strong> and writer.
             <% end %>
           <% end %>
         ERB
end
