# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_11) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. Drift
# found: the SNIPPETS entry showed the `type: :image` placeholder bare; the
# live block wraps it in `<div class="mb-2">...</div>` for spacing against
# the button placeholder below it. Ported with the wrapper included.
TablerUi::Docs::DemoRegistry.define(:placeholder) do |c|
  c.demo :variants,
         title: "text, avatar, image, button, list, animation",
         source: <<~'ERB'
           <%= tabler_ui.placeholder type: :text, lines: [10, 11, 8] %>
           <%= tabler_ui.placeholder type: :avatar %>
           <div class="mb-2"><%= tabler_ui.placeholder type: :image, ratio: "21x9" %></div>
           <%= tabler_ui.placeholder type: :button, width: 4, color: "primary" %>
           <%= tabler_ui.placeholder type: :text, width: 6, animation: :glow %>
         ERB
end
