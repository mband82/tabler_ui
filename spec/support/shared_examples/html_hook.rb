# frozen_string_literal: true

# Shared example group asserting the rule 5 HTML-hook contract (CLAUDE.md
# "5. HTML hooks on every subcomponent"): a component accepts `html:` for its
# root element, and `<part>_html:` for each named inner part; a caller's
# `class` is appended to the component's own classes (never replaces them),
# and other attributes (id, data-*, aria-*, ...) pass straight through onto
# the right element.
#
# Usage -- one line per hook a component exposes:
#
#   it_behaves_like "an element with an html hook", :badge, { text: "x" },
#     hook: :html, selector: ".badge"
#
#   it_behaves_like "an element with an html hook", :card, { title: "x" },
#     hook: :header_html, selector: ".card-header"
#
# Arguments:
#   component_name - Symbol passed to `render_component`/`component_fragment`
#                     (e.g. :badge), i.e. the name used as `tabler_ui.<name>`.
#   base_options    - Hash of the minimum kwargs needed to render the
#                      component successfully (without touching the hook
#                      under test).
#   hook:           - The HTML-hook keyword under test, e.g. :html,
#                      :header_html, :dialog_html.
#   selector:        - A CSS selector (passed to Nokogiri's #css) that finds
#                      the single element the hook targets. It's expected to
#                      include the component's own base class (e.g. ".badge",
#                      ".card-header"), so a match also proves that base class
#                      survived the merge.
#
# Requires `component_fragment` (see spec/support/component_helper.rb) to be
# available in the including example group, i.e. type: :component.
RSpec.shared_examples "an element with an html hook" do |component_name, base_options, hook:, selector:|
  def hook_fragment(component_name, base_options, hook, hook_options)
    component_fragment(component_name, **base_options.merge(hook => hook_options))
  end

  it "keeps the component's own class on the #{selector.inspect} element" do
    fragment = component_fragment(component_name, **base_options)

    expect(fragment.css(selector)).not_to be_empty,
      "expected #{selector.inspect} to match an element in:\n#{fragment.to_html}"
  end

  it "appends a caller-supplied class instead of replacing the component's own" do
    fragment = hook_fragment(component_name, base_options, hook, class: "hook-extra-class")
    element = fragment.css(selector).first

    expect(element).not_to be_nil,
      "expected #{selector.inspect} to still match after passing #{hook.inspect} class:, in:\n#{fragment.to_html}"

    classes = element["class"].to_s.split(/\s+/)
    expect(classes).to include("hook-extra-class")
    expect(classes.size).to be > 1, "expected the component's own class(es) to survive alongside the caller's, got: #{classes.inspect}"
  end

  it "passes through a caller-supplied id" do
    fragment = hook_fragment(component_name, base_options, hook, id: "hook-test-id")
    element = fragment.css(selector).first

    expect(element).not_to be_nil
    expect(element["id"]).to eq("hook-test-id")
  end

  it "passes through caller-supplied data attributes" do
    fragment = hook_fragment(component_name, base_options, hook, data: { testid: "hook-test-data" })
    element = fragment.css(selector).first

    expect(element).not_to be_nil
    expect(element["data-testid"]).to eq("hook-test-data")
  end
end
