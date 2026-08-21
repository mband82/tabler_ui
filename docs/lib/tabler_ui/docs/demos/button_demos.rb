# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_34 through
# content_39) -- the live example blocks, not the SNIPPETS hash, per
# docs/DEMOS.md. Three drifts found here:
#
# - content_36's snippet showed two buttons (Next, Refresh); the live block
#   renders a third ("Notify", animate_icon: "shake") demonstrating the third
#   named modifier. The snippet silently dropped it. Ported with all three.
# - content_37's snippet showed one button ("Ghost"); the live block renders
#   a second ("Ghost danger", color: "danger") to show ghost: true combined
#   with a non-primary color. The snippet dropped it. Ported with both.
# - content_38's snippet showed two brand buttons (GitHub, Facebook outline);
#   the live block renders four (GitHub, Twitter, Facebook outline, Muted).
#   The snippet dropped "Twitter" and "Muted". Ported with all four.
TablerUi::Docs::DemoRegistry.define(:button) do |c|
  c.demo :shape,
         title: "shape: 'pill' (btn-pill, wider padding) vs. default",
         source: <<~'ERB'
           <%= tabler_ui.button text: "Default", color: "primary" %>
           <%= tabler_ui.button text: "Pill", color: "primary", shape: "pill" %>
         ERB

  c.demo :loading,
         title: "loading: true (sets pointer-events: none only; pair with disabled: true for a real disable)",
         source: <<~'ERB'
           <%= tabler_ui.button text: "Saving...", color: "primary", loading: true, disabled: true %>
         ERB

  c.demo :animate_icon,
         title: "animate_icon (hover to see the effect): true = default slide, plus named modifiers",
         source: <<~'ERB'
           <%= tabler_ui.button text: "Next", color: "primary", icon: "arrow-right", animate_icon: true %>
           <%= tabler_ui.button text: "Refresh", color: "primary", icon: "refresh", animate_icon: "rotate" %>
           <%= tabler_ui.button text: "Notify", color: "primary", icon: "bell", animate_icon: "shake" %>
         ERB

  c.demo :ghost,
         title: "ghost: true (transparent until hovered; combines with color:, raises with outline: true)",
         source: <<~'ERB'
           <%= tabler_ui.button text: "Ghost", color: "primary", ghost: true %>
           <%= tabler_ui.button text: "Ghost danger", color: "danger", ghost: true %>
         ERB

  c.demo :brand_colors,
         title: "brand colors (buttons only), plain and outlined",
         source: <<~'ERB'
           <%= tabler_ui.button text: "GitHub", color: "github" %>
           <%= tabler_ui.button text: "Twitter", color: "twitter" %>
           <%= tabler_ui.button text: "Facebook", color: "facebook", outline: true %>
           <%= tabler_ui.button text: "Muted", color: "muted" %>
         ERB

  c.demo :floating,
         title: "floating: true (position: fixed -- pinned to the viewport's bottom-left corner, not to this card; shown once)",
         source: <<~'ERB'
           <%= tabler_ui.button text: "Add", color: "primary", icon: "plus", floating: true %>
         ERB
end
