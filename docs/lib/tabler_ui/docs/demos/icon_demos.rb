# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_4) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found: the SNIPPETS entry already matched the live block.
TablerUi::Docs::DemoRegistry.define(:icon) do |c|
  c.demo :variants,
         title: "outline/filled, color, animations, rule 5 html:",
         source: <<~'ERB'
           <span class="me-3"><%= tabler_ui.icon icon: "heart" %></span>
           <span class="me-3"><%= tabler_ui.icon icon: "heart", filled: true, color: "danger" %></span>
           <span class="me-3"><%= tabler_ui.icon icon: "star", filled: true, color: "yellow", pulse: true %></span>
           <span class="me-3"><%= tabler_ui.icon icon: "refresh", rotate: true %></span>
           <span class="me-3"><%= tabler_ui.icon icon: "bell", tada: true %></span>
           <span class="me-3"><%= tabler_ui.icon icon: "user", html: { class: "me-2", data: { testid: "user-icon" } } %></span>
         ERB
end
