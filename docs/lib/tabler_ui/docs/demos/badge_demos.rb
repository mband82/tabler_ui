# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_1,
# content_24, content_25) -- the live example blocks there, not the
# SNIPPETS hash, since that's the ported source of truth per docs/DEMOS.md.
# For these three the SNIPPETS entries happened to already match; ported
# verbatim regardless so this file is what a reader compares against, not the
# showcase.
TablerUi::Docs::DemoRegistry.define(:badge) do |c|
  c.demo :colors,
         title: "colors, light, pill, outline, icon, notification",
         source: <<~'ERB'
           <%= tabler_ui.badge text: "New", color: "blue" %>
           <%= tabler_ui.badge text: "Pending", color: "yellow", light: true %>
           <%= tabler_ui.badge text: "4", color: "red", pill: true %>
           <%= tabler_ui.badge text: "Draft", color: "secondary", outline: true %>
           <%= tabler_ui.badge text: "Star", color: "yellow", icon: "star" %>
           <%= tabler_ui.badge color: "red", notification: true, blink: true %>
         ERB

  c.demo :dot,
         title: "dot: true (fixed 10px dot; raises if combined with text/icon/content)",
         source: <<~'ERB'
           <%= tabler_ui.badge color: "red", dot: true %>
           <%= tabler_ui.badge color: "green", dot: true %>
         ERB

  c.demo :icon_only,
         title: "icon_only: true (zeroes horizontal padding; raises if combined with text)",
         source: <<~'ERB'
           <%= tabler_ui.badge color: "blue", icon: "star", icon_only: true %>
         ERB
end
