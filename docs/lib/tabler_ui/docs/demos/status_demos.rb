# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_6) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found: the SNIPPETS entry already matched the live block.
TablerUi::Docs::DemoRegistry.define(:status) do |c|
  c.demo :variants,
         title: "dot, animated, standalone, indicator, light",
         source: <<~'ERB'
           <%= tabler_ui.status text: "Active", color: "green" %>
           <%= tabler_ui.status text: "Online", color: "green", dot: true %>
           <%= tabler_ui.status text: "Processing", color: "blue", dot: true, animated: true %>
           <%= tabler_ui.status text: "Pending", color: "yellow", light: true %>
           <%= tabler_ui.status color: "green", dot: true, standalone: true %>
           <%= tabler_ui.status color: "red", indicator: true, animated: true %>
         ERB
end
