# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_3,
# content_30, content_31) -- taking the live example block as the source of
# truth, not the SNIPPETS hash, per docs/DEMOS.md. Two real drifts found here:
#
# - content_30's snippet showed only the bare `tabler_ui.avatar ... cover:
#   true` call, dropping the wrapping banner div the live block actually
#   renders it against. `cover:` pulls the avatar up over a preceding
#   element via negative margin -- shown without that element, the effect is
#   invisible, so the snippet's reader saw code that didn't produce the
#   screenshot above it. The :cover demo below ports the wrapping div too.
# - content_31's snippet showed a single md-sized avatar; the live block
#   showed two (md and xl, each wrapped in a spacing <span>) specifically to
#   compare how the overlay slot scales across sizes. The snippet silently
#   dropped the xl comparison. The :overlay demo below ports both.
TablerUi::Docs::DemoRegistry.define(:avatar) do |c|
  c.demo :basics,
         title: "initials, image, generated identicon, sizes, show_details",
         source: <<~'ERB'
           <%= tabler_ui.avatar initials: "JD", size: "md" %>
           <%= tabler_ui.avatar image: "https://picsum.photos/200", size: "md" %>
           <%= tabler_ui.avatar name: "Ada Lovelace", size: "md" %>
           <%= tabler_ui.avatar initials: "SM", size: "xl" %>
           <%= tabler_ui.avatar initials: "JD", show_details: true, title: "Jane Doe", subtitle: "Admin" %>
         ERB

  c.demo :cover,
         title: "cover: true (pulls the avatar up over a banner via negative margin)",
         source: <<~'ERB'
           <div>
             <div class="bg-blue" style="height: 60px; border-radius: 4px;"></div>
             <%= tabler_ui.avatar initials: "JD", size: "xl", cover: true %>
           </div>
         ERB

  c.demo :overlay,
         title: "overlay slot for a status dot, shown at size md and xl to compare scaling",
         source: <<~'ERB'
           <span class="me-3"><%= tabler_ui.avatar initials: "JD", size: "md" do |slots| %>
             <% slots.overlay do %><%= tag.span(class: "badge bg-success") %><% end %>
           <% end %></span>
           <span><%= tabler_ui.avatar initials: "SM", size: "xl" do |slots| %>
             <% slots.overlay do %><%= tag.span(class: "badge bg-success") %><% end %>
           <% end %></span>
         ERB
end
