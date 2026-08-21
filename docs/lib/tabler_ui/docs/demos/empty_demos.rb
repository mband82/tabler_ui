# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_16,
# content_17) -- the live example blocks, not the SNIPPETS hash, per
# docs/DEMOS.md. Each demo lived inside a `<div class="row row-cards">` /
# `<div class="col-md-6">` grid wrapper purely for page layout; that wrapper
# sits outside the `render layout: "showcase/example" do ... end` block and
# is not ported. No other drift found -- SNIPPETS entries otherwise matched
# the live block.
TablerUi::Docs::DemoRegistry.define(:empty) do |c|
  c.demo :action,
         title: "title, subtitle, illustration, action",
         source: <<~'ERB'
           <%= tabler_ui.empty image: "search", title: "No results found",
                               subtitle: "Try adjusting your search or filter." do |slots| %>
             <% slots.action do %>
               <%= tabler_ui.button text: "Clear filters", url: "#" %>
             <% end %>
           <% end %>
         ERB

  c.demo :bordered,
         title: "header, icon instead of illustration, bordered",
         source: <<~'ERB'
           <%= tabler_ui.empty icon: "mood-empty", header: "404",
                               title: "Page not found", bordered: true %>
         ERB
end
