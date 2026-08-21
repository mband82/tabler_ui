# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_2,
# content_27, content_28, content_29). The SNIPPETS entry for content_29
# wraps the call onto two lines where the live block is one line -- purely
# cosmetic, no semantic drift, but ported from the live block regardless per
# docs/DEMOS.md's rule to always treat it as the source of truth.
TablerUi::Docs::DemoRegistry.define(:alert) do |c|
  c.demo :colors,
         title: "colors, dismissible, important, icon, action link",
         source: <<~'ERB'
           <%= tabler_ui.alert color: "success", text: "Your changes have been saved!" %>
           <%= tabler_ui.alert color: "danger", title: "Error", text: "Something went wrong.", dismissible: true %>
           <%= tabler_ui.alert color: "warning", text: "Your trial expires in 3 days.", important: true %>
           <%= tabler_ui.alert color: "info", text: "New update available.", url: "#", link_text: "See what's new" %>
         ERB

  c.demo :minor,
         title: "minor: true (transparent background, neutral border)",
         source: <<~'ERB'
           <%= tabler_ui.alert color: "info", text: "Minor style alert.", minor: true %>
         ERB

  c.demo :muted,
         title: "color: 'muted' (alert-only colour value)",
         source: <<~'ERB'
           <%= tabler_ui.alert color: "muted", text: "Muted alert." %>
         ERB

  c.demo :link_style,
         title: "link_style: :action (underlined action link instead of the default alert-link)",
         source: <<~'ERB'
           <%= tabler_ui.alert color: "info", text: "New update available.", url: "#", link_text: "See what's new", link_style: :action %>
         ERB
end
