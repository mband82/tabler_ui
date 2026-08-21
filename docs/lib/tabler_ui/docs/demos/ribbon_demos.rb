# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_12,
# content_13) -- the live example blocks, not the SNIPPETS hash, per
# docs/DEMOS.md. Each demo lived inside a `<div class="row row-cards">` /
# `<div class="col-md-6">` grid wrapper purely for page layout; that wrapper
# sits outside the `render layout: "showcase/example" do ... end` block and
# is not ported. No other drift found -- SNIPPETS entries otherwise matched
# the live block, including the card wrapper each ribbon is pinned to (the
# ribbon component positions itself against a `position-relative` ancestor,
# so that wrapper is part of the demo, not incidental page layout).
TablerUi::Docs::DemoRegistry.define(:ribbon) do |c|
  c.demo :corner,
         title: "corner label on a card",
         source: <<~'ERB'
           <div class="card position-relative">
             <%= tabler_ui.ribbon text: "New", color: "blue" %>
             <div class="card-body">Ribbon pinned to the card's top-right corner.</div>
           </div>
         ERB

  c.demo :bookmark,
         title: "bookmark shape, bottom/start",
         source: <<~'ERB'
           <div class="card position-relative">
             <%= tabler_ui.ribbon text: "Sale", color: "red", position: :bottom, align: :start, bookmark: true %>
             <div class="card-body">Bookmark-shaped ribbon, bottom-left.</div>
           </div>
         ERB
end
