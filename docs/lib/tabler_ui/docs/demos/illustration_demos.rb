# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_5) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found: the SNIPPETS entry already matched the live block.
TablerUi::Docs::DemoRegistry.define(:illustration) do |c|
  c.demo :theme,
         title: "light/dark theme, sized",
         source: <<~'ERB'
           <%= tabler_ui.illustration name: "search", size: :sm %>
           <%= tabler_ui.illustration name: "search", theme: "dark", size: :sm %>
         ERB
end
