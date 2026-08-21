# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_7,
# content_32, content_33). Live blocks and SNIPPETS entries already matched
# for all three -- no drift found here -- ported from the live block anyway
# per docs/DEMOS.md so this file is what a reader checks against, not the
# showcase.
TablerUi::Docs::DemoRegistry.define(:progress) do |c|
  c.demo :variants,
         title: "auto color, striped/animated, labeled",
         source: <<~'ERB'
           <%= tabler_ui.progress percent: 42 %>
           <%= tabler_ui.progress percent: 82, color: "auto" %>
           <%= tabler_ui.progress percent: 95, color: "auto" %>
           <%= tabler_ui.progress percent: 60, striped: true, animated: true %>
           <%= tabler_ui.progress percent: 60, label: "Uploading", show_percent: true %>
         ERB

  c.demo :indeterminate,
         title: "indeterminate: true (animated unknown-progress bar; raises if combined with percent:)",
         source: <<~'ERB'
           <%= tabler_ui.progress indeterminate: true %>
         ERB

  c.demo :separated,
         title: "separated: true (draws a ring per bar; only visible with several bars on one track, which is progress-stacked and not built yet -- inert here for now)",
         source: <<~'ERB'
           <%= tabler_ui.progress percent: 60, separated: true %>
         ERB
end
