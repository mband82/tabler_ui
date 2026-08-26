# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"

# Regression guard for two bugs, both the same underlying cause: ERB's
# scanner does a naive text scan for "%>" with no awareness that it's
# already inside a `<%# %>` comment, so any literal "%>" written inside a
# comment's own text -- however it got there -- closes the comment early
# and leaks the rest of that comment's text as visible page content.
#
#   1. docs/app/views/tabler_ui/docs/shared/_search.html.erb's header
#      comment used to contain an escaped example tag
#      (`<%%= render "..." %>`), whose own closing sequence closed the
#      comment early.
#   2. docs/app/views/tabler_ui/docs/components/show.html.erb's @example
#      comment used to spell out the literal output tag around
#      `example.code` inline in prose, with the exact same effect.
#
# Both are fixed by never writing that two-character closing sequence
# inside a comment's text at all. The generic check here (no literal "%>"
# anywhere in rendered output) is the real guard, not a check against
# either bug's specific wording -- a properly-closed ERB comment can never
# leak that substring into HTML output, and @example blocks elsewhere in
# the docs are printed escaped (ERB::Util.html_escape turns "%>" into
# "%&gt;"), so this can't false-positive on legitimate code samples.
RSpec.describe "TablerUi::Docs pages render no leaked ERB comment text", type: :request do
  def assert_clean(path)
    get path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("%>")
    expect(response.body).not_to include("never a wrapper around it")
  end

  it "renders the index with no stray ERB comment text" do
    assert_clean("/ui")
  end

  it "renders the forms harness with no stray ERB comment text" do
    assert_clean("/ui/forms")
  end

  it "renders the HTML attributes page with no stray ERB comment text" do
    assert_clean("/ui/html-attributes")
  end

  it "renders the design editor with no stray ERB comment text" do
    assert_clean("/ui/editor")
  end

  it "renders the design editor's preview frame with no stray ERB comment text" do
    assert_clean("/ui/editor/frame")
  end

  TablerUi::Docs::Navigation.components.each do |name|
    it "renders /ui/components/#{name} with no stray ERB comment text" do
      assert_clean("/ui/components/#{name}")
    end
  end
end
