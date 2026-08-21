# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_8,
# content_9, content_10) -- the live example blocks, not the SNIPPETS hash,
# per docs/DEMOS.md. Each demo lived inside a `<div class="row row-cards">` /
# `<div class="col-md-4">` grid wrapper in the old page purely for layout;
# that wrapper is outside the `render layout: "showcase/example" do ... end`
# block itself, so it is not part of the live block and is not ported. No
# other drift found -- the SNIPPETS entries otherwise matched the live block.
TablerUi::Docs::DemoRegistry.define(:stat_card) do |c|
  c.demo :positive_trend,
         title: "positive trend",
         source: <<~'ERB'
           <%= tabler_ui.stat_card label: "Sales", value: "456", icon: "shopping-cart", trend: 12 %>
         ERB

  c.demo :negative_trend,
         title: "negative trend, description, link",
         source: <<~'ERB'
           <%= tabler_ui.stat_card label: "New clients", value: "18", trend: -8,
                                   description: "vs. last month", url: "#" %>
         ERB

  c.demo :colored_icon,
         title: "colored icon",
         source: <<~'ERB'
           <%= tabler_ui.stat_card label: "Revenue", value: "$9,600", icon: "currency-dollar", color: "green" %>
         ERB
end
