# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/toc_label"

# TablerUi::Docs::TocLabel (docs/lib/tabler_ui/docs/toc_label.rb) -- shortens
# a Demo or Section title for the Contents column
# (docs/app/views/tabler_ui/docs/components/show.html.erb) only. Demo titles
# are full descriptive one-liners written for the demo card heading; reused
# verbatim as a nav label they're hard to scan, so this cuts a long one at
# its first natural break instead of requiring a second, shorter title to be
# authored per demo (see docs/DEMOS.md -- unchanged by this feature).
RSpec.describe TablerUi::Docs::TocLabel do
  describe ".shorten" do
    it "returns a title of 60 characters or fewer unchanged" do
      title = "a" * 60
      expect(described_class.shorten(title)).to eq(title)
    end

    it "strips a trailing parenthetical explanation, real example from table_demos.rb" do
      title = "frame: (Turbo Frame: sorting, filtering and paging without a page reload; pager in footer:; " \
              'search button: "Search"; filter min_chars: 3)'
      expect(title.length).to be > 60 # guards the premise

      expect(described_class.shorten(title)).to eq("frame:")
    end

    it "strips a trailing parenthetical explanation, real example from button_demos.rb-style title" do
      title = "loading: true (sets pointer-events: none only; pair with disabled: true for a real disable)"
      expect(title.length).to be > 60 # guards the premise

      expect(described_class.shorten(title)).to eq("loading: true")
    end

    it "cuts at the first ' -- ' when there is no trailing parenthetical" do
      title = "a" * 40 + " -- " + "b" * 40
      expect(title.length).to be > 60 # guards the premise

      expect(described_class.shorten(title)).to eq("a" * 40)
    end

    it "cuts at the first ', ' when there is no parenthetical or ' -- '" do
      title = "a" * 40 + ", " + "b" * 40
      expect(title.length).to be > 60 # guards the premise

      expect(described_class.shorten(title)).to eq("a" * 40)
    end

    it "hard-truncates with an ellipsis when there is no natural break point" do
      title = "a" * 90
      result = described_class.shorten(title)

      expect(result.length).to eq(60)
      expect(result).to eq("#{"a" * 57}...")
    end

    it "hard-truncates with an ellipsis when the candidate after a break is still over 60 characters" do
      title = "a" * 90 + ", " + "b" * 5
      result = described_class.shorten(title)

      expect(result.length).to eq(60)
      expect(result).to eq("#{"a" * 57}...")
    end

    it "returns nil unchanged" do
      expect(described_class.shorten(nil)).to be_nil
    end

    it "returns an empty string unchanged" do
      expect(described_class.shorten("")).to eq("")
    end

    it "returns a blank (whitespace-only) string unchanged" do
      expect(described_class.shorten("   ")).to eq("   ")
    end
  end
end
