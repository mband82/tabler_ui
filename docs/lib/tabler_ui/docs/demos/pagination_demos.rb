# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_22) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found for this demo: the SNIPPETS entry already matched the live block.
#
# content_22's sibling, content_21 ("pagination - computed mode"), was NOT
# ported. Its live block is:
#
#   <% current_page = [[(params[:page] || 3).to_i, 1].max, 10].min %>
#   <%= tabler_ui.pagination current: current_page, total: 10,
#                            url: ->(n) { content_path(page: n) } %>
#
# Two problems, both controller/request state that a standalone demo file
# cannot supply: it reads `params[:page]` (drift note: the SNIPPETS entry for
# content_21 read `(params[:page] || 3).to_i` directly with no clamping,
# silently dropping the `[[..., 1].max, 10].min` clamp the live block
# performs -- a real behavioural difference, not cosmetic, since the
# unclamped snippet could pass an out-of-range `current:` straight through),
# and its `url:` lambda calls `content_path`, a route helper generated for
# the old showcase app's own routes, which does not exist in the docs
# engine. Per docs/DEMOS.md's `locals:` guidance and this port's
# instructions, a demo needing genuine controller state is skipped rather
# than faked with an invented mechanism -- not ported here.
TablerUi::Docs::DemoRegistry.define(:pagination) do |c|
  c.demo :size_circle_outline,
         title: "size: :sm, circle:, outline:",
         source: <<~'ERB'
           <%= tabler_ui.pagination current: 1, total: 5, url: ->(n) { "?page=#{n}" },
                                    size: :sm, circle: true, outline: true %>
         ERB
end
