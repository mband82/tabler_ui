# frozen_string_literal: true

# Ported from showcase/app/views/showcase/content.html.erb (content_23) --
# the live example block, not the SNIPPETS hash, per docs/DEMOS.md. No drift
# found against the SNIPPETS entry, but the live block itself needed a fix
# here: both calls omitted name:, so both got the component's deterministic
# default id ("rating-rating", see #default_id in
# app/components/tabler_ui/rating/component.rb) and collided once rendered
# together on one demo page. Each rating below now gets the name: a real
# form field would need anyway. See :multiple_same_name for the case where
# name: can't do that disambiguation and id: is the right tool instead.
TablerUi::Docs::DemoRegistry.define(:rating) do |c|
  c.demo :variants,
         title: "custom choices, colored, clearable",
         source: <<~'ERB'
           <%= tabler_ui.rating name: "quality" %>
           <%= tabler_ui.rating name: "delivery", choices: [{ value: 1, label: "Bad" }, { value: 2, label: "Ok" }, { value: 3, label: "Great" }],
                                max_stars: 3, color: "yellow", value: 2 %>
         ERB

  c.demo :multiple_same_name,
         title: "two ratings, same name: -- pass id: explicitly or their DOM ids collide",
         source: <<~'ERB'
           <%= tabler_ui.rating name: "overall", id: "overall-rating-reviewer-a", value: 4 %>
           <%= tabler_ui.rating name: "overall", id: "overall-rating-reviewer-b", value: 2 %>
         ERB
end
