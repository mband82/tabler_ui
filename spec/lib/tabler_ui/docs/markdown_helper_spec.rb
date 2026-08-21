# frozen_string_literal: true

require "rails_helper"

# TablerUi::Docs::MarkdownHelper (docs/app/helpers/tabler_ui/docs/
# markdown_helper.rb) -- a small, safe markdown subset (code spans, bullet
# lists, numbered lists, bold, paragraph breaks) applied to component
# description/section-body/option-description text before it renders on a
# docs page (see docs/app/views/tabler_ui/docs/components/show.html.erb).
# @example blocks are never run through this -- they stay verbatim escaped
# code, checked separately in components_page_spec.rb.
#
# No `require` here -- docs/app/helpers is autoloaded by
# TablerUi::Docs::Engine (a Rails::Engine's own app/helpers path, part of
# Rails' default per-engine `app/*` autoload paths) the same way
# docs/app/models/tabler_ui/docs/person_form.rb already is elsewhere in
# this spec suite (see spec/requests/tabler_ui/docs/forms_spec.rb) --
# unlike docs/lib/tabler_ui/docs/*.rb, which sits outside any autoload
# path and so every spec that touches it does `require
# "tabler_ui/docs/..."` explicitly (see e.g. navigation_spec.rb).
RSpec.describe TablerUi::Docs::MarkdownHelper do
  describe ".render" do
    it "returns an empty, html_safe string for nil or blank input" do
      expect(described_class.render(nil)).to eq("")
      expect(described_class.render(nil)).to be_html_safe
      expect(described_class.render("")).to eq("")
      expect(described_class.render("   ")).to eq("")
    end

    it "turns a backtick span into a <code> element" do
      result = described_class.render("call `tabler_ui.icon` here")

      expect(result).to include("<code>tabler_ui.icon</code>")
      expect(result).to be_html_safe
    end

    it "turns **text** into a <strong> element" do
      result = described_class.render("this is **important** text")

      expect(result).to include("<strong>important</strong>")
    end

    it "turns a '* ' line into a <ul><li> bullet list item" do
      result = described_class.render("intro line\n\n* first item\n* second item")

      expect(result).to include("<ul>")
      expect(result).to include("<li>first item</li>")
      expect(result).to include("<li>second item</li>")
    end

    it "turns a '1. ' line into an <ol><li> numbered list item" do
      result = described_class.render("* not a bullet marker escaped, real content:\n\n1. first step\n2. second step")

      expect(result).to include("<ol>")
      expect(result).to include("<li>first step</li>")
      expect(result).to include("<li>second step</li>")
    end

    it "folds an indented continuation line into the previous list item, not a new paragraph" do
      result = described_class.render("* first item spans\n  a second physical line")

      expect(result).to include("<li>first item spans a second physical line</li>")
    end

    it "splits blank-line-separated text into separate <p> paragraphs" do
      result = described_class.render("first paragraph\n\nsecond paragraph")

      expect(result).to include("<p>first paragraph</p>")
      expect(result).to include("<p>second paragraph</p>")
    end

    # The critical safety property: escape first, transform second, so the
    # result is safe by construction -- see the class docs' "Why escape
    # first" section. This is the one example this task explicitly calls
    # for: a string containing HTML must be escaped, never injected.
    it "escapes rather than injects a string containing HTML" do
      result = described_class.render("<script>alert('xss')</script>")

      expect(result).not_to include("<script>")
      expect(result).to include("&lt;script&gt;")
      expect(result).to be_html_safe
    end

    it "escapes HTML found alongside real markdown, rather than letting it through untouched" do
      result = described_class.render("call `<img onerror=alert(1)>` here")

      expect(result).not_to include("<img")
      expect(result).to include("<code>&lt;img onerror=alert(1)&gt;</code>")
    end
  end

  # Regression guard for a real outage this task shipped and caught before
  # landing: an earlier version of this module defined its methods via
  # `module_function`, which -- on top of the singleton `MarkdownHelper.render`
  # every view calls -- also creates a *private instance-method* copy of
  # `render`. Because this file lives under docs/app/helpers/ and is named
  # "*_helper.rb"/"*Helper" (the exact convention Rails::Engine's
  # `include_all_helpers` auto-mixes into every view), that private instance
  # method ended up in every view's own ancestor chain and shadowed
  # ActionView::Helpers::RenderingHelper#render -- so every single component
  # any docs page rendered (via lib/tabler_ui/ui.rb#render_component's
  # `@view.render(...)`) raised "private method 'render' called for an
  # instance of ...". Every docs page 500'd. The unit examples above, which
  # call `described_class.render` directly, kept passing the entire time --
  # they never exercise a real view's ancestor chain. Only a real HTTP
  # request through a real view does, which is what this renders now.
  describe "integration: rendered on a real docs page", type: :request do
    it "renders /ui/components/table as 200, with its description run through the markdown helper" do
      parsed = TablerUi::Docs::DocParser.find("table")
      expect(parsed.description).to be_present # guards the premise: table still has a description to render

      get "/ui/components/table"
      expect(response).to have_http_status(:ok)

      # A plain substring check against the raw response body, not a
      # Nokogiri-parsed-and-reserialized comparison: HTML5 serializers are
      # free to drop escaping that isn't strictly required outside `<`
      # (e.g. a bare "&gt;" in text content round-trips back out as a
      # literal ">"), so comparing re-serialized DOM output against this
      # helper's own raw string would compare two different, both-valid
      # encodings of the same markup instead of proving they match.
      expect(response.body).to include(TablerUi::Docs::MarkdownHelper.render(parsed.description))
    end
  end
end
