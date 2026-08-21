# frozen_string_literal: true

# Ported from showcase/app/views/showcase/forms.html.erb (forms_1..forms_20)
# -- the live example blocks there, not showcase/app/helpers/showcase_helper.rb's
# SNIPPETS hash, per docs/DEMOS.md's porting rule. One real drift found:
#
# - forms_20 (as: :input_group): the SNIPPETS entries used bare
#   `label: "Salary"` / `label: "Website"`. The live block actually passed
#   `label: "Salary (as: :input_group)"` / `label: "Website (as: :input_group)"`
#   -- the snippet's reader would have seen plain labels that don't match
#   the rendered example above them. Ported from the live block, the
#   "(as: :input_group)" suffix included -- see the :input_group demo below.
#
# Every other forms_N snippet matched its live block (only cosmetic
# line-wrapping differed in a couple of spots, e.g. forms_10/forms_12) --
# still ported from the live block regardless, on the same principle as the
# five reference components: this file is what a reader now checks the
# rendered example against, not the old showcase.
#
# One more deviation from the live block's literal text, not a drift: the
# :input_group demo adds `input_html: { id: ... }` to its :salary/:website
# fields, which forms_20 did not have. See the comment on that demo below
# for why -- short version, spec/lib/tabler_ui/docs/demo_ids_spec.rb asserts
# no duplicate id= attribute across a component's demos rendered together,
# and :salary/:website each already appear in an earlier demo.
#
# THE TYPE-INFERENCE CONTRADICTION (forms_19 / :inferred_types):
# showcase_controller.rb's PersonForm had a NOTE: comment claiming
# FormBuilder's type inference *fails* for a plain ActiveModel::Attributes
# object (every field "silently falls back to a plain text input"), while
# forms.html.erb's own forms_19 block claimed the *opposite* -- that
# inference works and appointment_at/salary render as datetime-local/number
# fields with no `as:`. Checked empirically (render both fields, inspect the
# emitted type= attribute) rather than trusted either comment:
# TablerUi::FormBuilder#object_type_for_method (lib/tabler_ui/form_builder.rb)
# has a class-level fallback via `@object.class.attribute_types` for exactly
# this case, and rendering confirms it -- appointment_at emits
# `type="datetime-local"`, salary emits `type="number" step="any"`. See
# docs/app/models/tabler_ui/docs/person_form.rb's NOTE: comment for the full
# writeup and spec/requests/tabler_ui/docs/forms_spec.rb for the request-spec
# assertion on the actual markup. forms.html.erb's explanation was the
# accurate one and is ported into the :inferred_types demo below verbatim;
# showcase_controller.rb's "demonstrates the gap" claim was wrong and is not
# carried over anywhere.
#
# THE STRUCTURE: unlike the five reference components, these demos are
# fragments that only make sense inside a form -- each one is
# `<%= f.input ... %>` referencing a bare `f` local (a TablerUi::FormBuilder),
# not a `tabler_ui.foo` call. The real wrapping `tabler_form_with` is a
# harness, not a demo, and stays hand-written in
# docs/app/views/tabler_ui/docs/forms/show.html.erb (see that file and
# docs/app/views/tabler_ui/docs/demos/_form_demo.html.erb for how the live,
# request-bound `f` gets threaded into each demo's `locals:` on that page).
# Every demo below still needs to render standalone too, though --
# spec/lib/tabler_ui/docs/demo_registry_spec.rb's "every registered demo
# renders" example calls `resolved_locals` directly, with no live `f` to
# merge in -- so each demo's own `locals:` proc builds a private, throwaway
# `f` via FormBuilderDemoFixture below. That fallback is what actually runs
# on /ui/demos/form_builder (the generic per-component route); the real
# harness at /ui/forms overrides it with the live one.
module TablerUi
  module Docs
    # Builds a fresh, self-contained `{ f: TablerUi::FormBuilder }` locals
    # hash for a form_builder demo to render standalone -- a real view
    # context (so text_field/number_field/etc. and the `icon`/`rating`
    # components f.toggle_button/f.input(as: :rating) delegate to actually
    # resolve) wrapped around a fresh TablerUi::Docs::PersonForm.sample.
    # Called lazily, once per render, by each demo's `locals:` proc below --
    # never at registration time (see Demo#resolved_locals) -- so nothing is
    # built for a demo that's never rendered on the current page.
    module FormBuilderDemoFixture
      class << self
        def locals
          { f: build_form_builder }
        end

        private

        def build_form_builder
          view_paths = ActionView::PathSet.new([TablerUi::Engine.root.join("app/components").to_s])
          view_class = ActionView::Base.with_empty_template_cache
          view_class.include(TablerUi::Helper)
          view = view_class.with_view_paths(view_paths, {})
          TablerUi::FormBuilder.new(:person, PersonForm.sample, view, {})
        end
      end

      # Shared across every demo below -- same Proc object, called fresh
      # each time (Demo#resolved_locals only ever calls it, never memoizes
      # the result), so every demo gets its own fresh f/PersonForm.
      LOCALS = -> { FormBuilderDemoFixture.locals }
    end
  end
end

TablerUi::Docs::DemoRegistry.define(:form_builder) do |c|
  c.demo :name,
         title: "f.input :name -- default :string",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :name, hint: "Full legal name", required: true %>
         ERB

  c.demo :email,
         title: "f.input :email -- name-pattern email_field",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :email, label_description: "we'll never share it" %>
         ERB

  c.demo :bio,
         title: "f.input :bio, as: :text",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :bio, as: :text, input_html: { rows: 3 } %>
         ERB

  c.demo :date_picker,
         title: "f.input :birthday, as: :date_picker",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :birthday, as: :date_picker %>
         ERB

  c.demo :phone,
         title: "f.input :phone -- name-pattern telephone_field",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :phone %>
         ERB

  c.demo :floating,
         title: "f.input :website, as: :floating",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :website, as: :floating, label: "Website" %>
         ERB

  c.demo :toggle_switch,
         title: "f.toggle_switch :newsletter",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.toggle_switch :newsletter, description: "Product updates, once a month" %>
         ERB

  c.demo :toggle_button,
         title: "f.toggle_button :bio_notifications, color:, icon:",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.toggle_button :bio_notifications, color: "success", icon: "bell", text: "Notify on profile views" %>
         ERB

  c.demo :radio_buttons,
         title: "f.input :plan, as: :radio_buttons, selectgroup_buttons: true",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :plan, as: :radio_buttons, collection: %w[free pro enterprise], selectgroup_buttons: true %>
         ERB

  c.demo :check_boxes,
         title: "f.input :interests, as: :check_boxes, selectgroup_pills: true",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :interests, as: :check_boxes, collection: %w[Design Engineering Marketing Sales], selectgroup_pills: true %>
         ERB

  c.demo :select,
         title: "f.input :role, as: :select",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :role, as: :select, collection: %w[admin editor viewer] %>
         ERB

  c.demo :grouped_select,
         title: "f.input :team, as: :grouped_select",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :team, as: :grouped_select, collection: { "Engineering" => %w[backend frontend], "Product" => %w[design research] } %>
         ERB

  c.demo :association,
         title: "f.association :manager_id -- no reflection, falls back to select",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.association :manager_id, collection: %w[Alice Bob Carol] %>
         ERB

  c.demo :color,
         title: "f.input :color, as: :color",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :color, as: :color %>
         ERB

  c.demo :rating,
         title: "f.input :avatar_rating, as: :rating",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :avatar_rating, as: :rating, max_stars: 5, color: "yellow" %>
         ERB

  c.demo :imagecheck,
         title: "f.input :theme, as: :imagecheck",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :theme, as: :imagecheck, show_text: true,
                               value_method: :id, image_method: :image_url, text_method: :label,
                               collection: [
                                 OpenStruct.new(id: "blue", image_url: "https://picsum.photos/seed/blue/80", label: "Blue"),
                                 OpenStruct.new(id: "green", image_url: "https://picsum.photos/seed/green/80", label: "Green")
                               ] %>
         ERB

  c.demo :file,
         title: "f.input :resume, as: :file",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :resume, as: :file, hint: "PDF, up to 5MB" %>
         ERB

  c.demo :input_field,
         title: "f.input_field -- naked input, no wrapper/label",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input_field :search_query, input_html: { placeholder: "Naked input, no label/wrapper" } %>
         ERB

  c.demo :inferred_types,
         title: "f.input :appointment_at / :salary -- inferred types",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <p class="text-secondary">
             <code>appointment_at</code> is a <code>:datetime</code> attribute and <code>salary</code> a
             <code>:decimal</code> one. <code>TablerUi::FormBuilder</code> infers both from the model and
             renders a native <code>datetime-local</code> field and a <code>number</code> field with
             <code>step="any"</code> -- no <code>as:</code> needed. This works for plain
             <code>ActiveModel::Attributes</code> objects as well as ActiveRecord ones, because
             <code>object_type_for_method</code> falls back to the class-level
             <code>attribute_types</code> that ActiveModel exposes.
           </p>
           <%= f.input :appointment_at %>
           <%= f.input :salary %>
         ERB

  # NOTE: :salary and :website each already appear in an earlier demo above
  # (:inferred_types, :floating) -- Rails' default id="person_salary" /
  # id="person_website" would repeat verbatim here otherwise. The live
  # showcase block had no id override (both demos sat in the same one real
  # <form>, so this duplicate-id bug was already latent there, just never
  # asserted). spec/lib/tabler_ui/docs/demo_ids_spec.rb DOES assert it,
  # across every demo of a component rendered together (as the generic
  # /ui/demos/:component route does) -- so `input_html: { id: ... }` is
  # added here, the one deviation from the live block's literal text, to
  # keep this demo's ids unique on that page. Purely a DOM-id fix; every
  # option that's part of what this demo demonstrates (as:, prepend:,
  # append:, label:) is unchanged.
  c.demo :input_group,
         title: "f.input as: :input_group",
         locals: TablerUi::Docs::FormBuilderDemoFixture::LOCALS,
         source: <<~'ERB'
           <%= f.input :salary, as: :input_group, prepend: "$", label: "Salary (as: :input_group)", input_html: { id: "person_salary_input_group" } %>
           <%= f.input :website, as: :input_group, append: ".com", label: "Website (as: :input_group)", input_html: { id: "person_website_input_group" } %>
         ERB
end
