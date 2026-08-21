# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_19) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found: the SNIPPETS entry already matched the live block.
TablerUi::Docs::DemoRegistry.define(:steps) do |c|
  c.demo :variants,
         title: "current progress, vertical, counter, color",
         source: <<~'ERB'
           <%= tabler_ui.steps(current: 2, counter: true, color: "azure") do |steps| %>
             <% steps.item("Account", url: "#") %>
             <% steps.item("Profile", url: "#") %>
             <% steps.item("Confirm") %>
           <% end %>
         ERB
end
