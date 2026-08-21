# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_14) --
# taking the live example block as the source of truth per docs/DEMOS.md.
# Minor drift found: the SNIPPETS entry showed four bare `tabler_ui.spinner`
# calls; the live block wraps each in `<span class="me-3">` so the four
# render side by side with visible gaps instead of touching. Cosmetic, but
# it is what actually produced the rendered example, so it is what is ported.
TablerUi::Docs::DemoRegistry.define(:spinner) do |c|
  c.demo :variants,
         title: "border/grow, sizes, colors, custom label",
         source: <<~'ERB'
           <span class="me-3"><%= tabler_ui.spinner %></span>
           <span class="me-3"><%= tabler_ui.spinner type: :grow %></span>
           <span class="me-3"><%= tabler_ui.spinner size: "sm", color: "blue" %></span>
           <span class="me-3"><%= tabler_ui.spinner label: "Saving..." %></span>
         ERB
end
