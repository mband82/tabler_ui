# frozen_string_literal: true

# Shared example group asserting the CLAUDE.md rule 8 `auth:` contract: a
# component renders when the globally configured auth_method authorizes its
# `auth:` value, renders nothing when it doesn't, and the auth_method
# receives that exact value.
#
# Unlike spec/support/shared_examples/html_hook.rb, this is deliberately NOT
# wired into every component spec. The `auth:` gate lives entirely in
# TablerUi::Ui#method_missing (see lib/tabler_ui/ui.rb) -- every component
# goes through the exact same code path, already covered end-to-end by
# spec/lib/tabler_ui/authorization_spec.rb and the "auth: gating" section of
# spec/lib/tabler_ui/ui_spec.rb. It's included here in only 2 component
# specs, as a representative sanity check that the mechanism reaches real
# components -- not as an attempt at exhaustive per-component coverage:
#
#   spec/components/button_spec.rb - modern class-backed, no block
#   spec/components/card_spec.rb   - modern class-backed, slot-style block
#
# A third shape was planned -- an OpenStruct bare-partial component -- but as
# of this writing every one of the 35 shipped components has been converted
# to a class-backed one (`app/components/tabler_ui/<name>/component.rb`);
# CLAUDE.md's "Bare partials" section describing `_button`/`_card`/etc. as
# still-bare is stale. The OpenStruct path itself still exists (see
# lib/tabler_ui/ui.rb's build_open_struct_component, kept as a host-app
# extension point) and is exercised for `auth:` in ui_spec.rb's "auth:
# gating" section via the spec_bare fixture -- there's just no *shipped*,
# spec'd bare-partial component left to hang this shared example off of. If
# one is added back later, wire it in as the third example here rather than
# assuming this list is exhaustive.
#
# Do not "complete" this rollout by adding it to the other ~30 component
# specs; that would be repetitive, not more correct.
#
# Usage:
#
#   it_behaves_like "an element with an auth option", :button, { text: "x" }
#
# Arguments:
#   component_name - Symbol passed to `render_component`/`component_fragment`
#                     (e.g. :button), i.e. the name used as `tabler_ui.<name>`.
#   base_options    - Hash of the minimum kwargs needed to render the
#                      component successfully, without an `auth:` key --
#                      this shared example adds its own.
#
# Requires `render_component`/`component_fragment` (see
# spec/support/component_helper.rb) to be available in the including example
# group, i.e. type: :component.
RSpec.shared_examples "an element with an auth option" do |component_name, base_options|
  # TablerUi.auth_method is global, process-wide mutable state -- restore it
  # after every example so it can never leak into a spec that runs later.
  around do |example|
    original = TablerUi.auth_method
    example.run
    TablerUi.auth_method = original
  end

  it "renders when the configured auth_method authorizes the auth: value" do
    TablerUi.auth_method = ->(_value) { true }

    fragment = component_fragment(component_name, **base_options.merge(auth: :some_permission))

    expect(fragment.children).not_to be_empty
  end

  it "renders nothing when the configured auth_method denies the auth: value" do
    TablerUi.auth_method = ->(_value) { false }

    result = render_component(component_name, **base_options.merge(auth: :some_permission))

    expect(result).to be_nil
  end

  it "passes the auth: value through to the configured auth_method" do
    received = []
    TablerUi.auth_method = ->(value) { received << value; true }

    render_component(component_name, **base_options.merge(auth: :some_permission))

    expect(received).to eq([:some_permission])
  end
end
