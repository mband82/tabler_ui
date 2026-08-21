# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/navigation"

# Regression guard for the "Rule 5" jargon leak: component.rb comments used
# to point readers at "Rule 5" -- a rule number from this repo's own
# CLAUDE.md, meaningless to anyone reading the public docs site. Fixed by
# rewording every such comment to plain "HTML attributes" language (see the
# cross-cutting /ui/html-attributes page for the one place the mechanism
# itself is explained).
#
# Two layers, because either one rotting independently would ship the bug
# again: a source-level check on the doc comments themselves (cheap, exact,
# catches it before it ever reaches a page), and a rendered-page check
# (catches the case where a comment stays clean but some other doc string
# -- static ERB copy, a demo caption -- reintroduces the phrase where a
# reader would actually see it).
RSpec.describe "TablerUi docs carry no internal jargon" do
  component_files = Dir.glob(
    File.expand_path("../../../../app/components/tabler_ui/*/component.rb", __dir__)
  )

  it "found component.rb files to check (sanity check on the glob itself)" do
    expect(component_files).not_to be_empty
  end

  component_files.each do |path|
    name = path.sub("#{Dir.pwd}/", "")

    it "#{name} contains no 'Rule 5' reference" do
      expect(File.read(path)).not_to match(/rule 5/i)
    end
  end

  describe "rendered docs pages", type: :request do
    def assert_no_jargon(path)
      get path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/rule 5/i)
    end

    it "renders the index with no 'Rule 5' reference" do
      assert_no_jargon("/ui")
    end

    it "renders the forms harness with no 'Rule 5' reference" do
      assert_no_jargon("/ui/forms")
    end

    it "renders the html-attributes page with no 'Rule 5' reference" do
      assert_no_jargon("/ui/html-attributes")
    end

    TablerUi::Docs::Navigation.components.each do |component_name|
      it "renders /ui/components/#{component_name} with no 'Rule 5' reference" do
        assert_no_jargon("/ui/components/#{component_name}")
      end
    end
  end
end
