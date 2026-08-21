# frozen_string_literal: true

# Ported from showcase/app/views/showcase/layout.html.erb (the render layout:
# "showcase/example" blocks for "tabs - style: :pills, icons, badges",
# "tabs - style: :tabs, :pills, :underline, :bordered, :segmented side by
# side", "tabs - fill: true", and "tabs - style: :segmented, vertical: true")
# -- the live example blocks, not SNIPPETS[:layout_7]/[:layout_25..27], per
# docs/DEMOS.md.
#
# Real drift found in :styles (content_25/layout_25): SNIPPETS[:layout_25]
# shows only two variants -- default (:tabs) and :pills -- as two separate
# calls with a comment ("style: also accepts :pills, :underline, :bordered,
# :segmented") gesturing at the rest without rendering them. The live block
# renders all five styles (:tabs, :pills, :underline, :bordered, :segmented)
# side by side in a row-cards grid, each labelled and each with its own id
# (style-tabs-demo, style-pills-demo, style-underline-demo,
# style-bordered-demo, style-segmented-demo) -- a materially different (and
# more complete) demo than the snippet's two-variant version with
# demo-tabs/demo-tabs-pills ids. Ported from the live block, all five
# variants included.
#
# :pills, :fill and :segmented_vertical had no drift -- their live blocks
# matched SNIPPETS[:layout_7]/[:layout_26]/[:layout_27] exactly -- but were
# still ported from the live block rather than the snippet, per docs/DEMOS.md.
TablerUi::Docs::DemoRegistry.define(:tabs) do |c|
  c.demo :pills,
         title: "style: :pills, icons, badges",
         source: <<~'ERB'
           <%= tabler_ui.tabs("demo-tabs", style: :pills) do |tabs| %>
             <% tabs.tab("Inbox", icon: "mail", badge: "3") do %>
               You have 3 unread messages.
             <% end %>
             <% tabs.tab("Sent", icon: "send") do %>
               Nothing new here.
             <% end %>
             <% tabs.tab("Archive", badge: { text: "12", color: "red" }) do %>
               12 archived threads.
             <% end %>
           <% end %>
         ERB

  c.demo :styles,
         title: "style: :tabs, :pills, :underline, :bordered, :segmented side by side",
         source: <<~'ERB'
           <div class="row row-cards">
             <div class="col">
               <div class="text-secondary mb-2">style: :tabs (default)</div>
               <%= tabler_ui.tabs("style-tabs-demo") do |tabs| %>
                 <% tabs.tab("One") { "First" } %>
                 <% tabs.tab("Two") { "Second" } %>
               <% end %>
             </div>
             <div class="col">
               <div class="text-secondary mb-2">style: :pills</div>
               <%= tabler_ui.tabs("style-pills-demo", style: :pills) do |tabs| %>
                 <% tabs.tab("One") { "First" } %>
                 <% tabs.tab("Two") { "Second" } %>
               <% end %>
             </div>
             <div class="col">
               <div class="text-secondary mb-2">style: :underline</div>
               <%= tabler_ui.tabs("style-underline-demo", style: :underline) do |tabs| %>
                 <% tabs.tab("One") { "First" } %>
                 <% tabs.tab("Two") { "Second" } %>
               <% end %>
             </div>
             <div class="col">
               <div class="text-secondary mb-2">style: :bordered</div>
               <%= tabler_ui.tabs("style-bordered-demo", style: :bordered) do |tabs| %>
                 <% tabs.tab("One") { "First" } %>
                 <% tabs.tab("Two") { "Second" } %>
               <% end %>
             </div>
             <div class="col">
               <div class="text-secondary mb-2">style: :segmented</div>
               <%= tabler_ui.tabs("style-segmented-demo", style: :segmented) do |tabs| %>
                 <% tabs.tab("One") { "First" } %>
                 <% tabs.tab("Two") { "Second" } %>
               <% end %>
             </div>
           </div>
         ERB

  c.demo :fill,
         title: "fill: true (equal-width tabs)",
         source: <<~'ERB'
           <%= tabler_ui.tabs("fill-tabs-demo", fill: true) do |tabs| %>
             <% tabs.tab("Inbox") { "First" } %>
             <% tabs.tab("Sent") { "Second" } %>
             <% tabs.tab("Archive") { "Third" } %>
           <% end %>
         ERB

  c.demo :segmented_vertical,
         title: "style: :segmented, vertical: true",
         source: <<~'ERB'
           <%= tabler_ui.tabs("segmented-vertical-demo", style: :segmented, vertical: true) do |tabs| %>
             <% tabs.tab("One") { "First" } %>
             <% tabs.tab("Two") { "Second" } %>
             <% tabs.tab("Three") { "Third" } %>
           <% end %>
         ERB
end
