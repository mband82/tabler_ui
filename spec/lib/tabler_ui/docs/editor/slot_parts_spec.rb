# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor/slot_map"
require "tabler_ui/docs/editor/slot_parts"

# SlotParts::PARTS is hand-maintained (see its module doc for why -- same
# reason as SlotMap::SLOTS: docs/lib is not autoloaded or reloaded, so
# deriving it at load time would only ever reflect server-boot state
# anyway). This spec re-derives the truth fresh, at runtime, straight from
# the real component sources, and asserts it against the constant.
#
# Unlike SlotMap's derivation (which only needs to know THAT a template
# calls `slots.<name>`), this one has to know WHERE that call's content
# lands relative to the template's own hooked wrappers -- a plain
# `slots\.(\w+)` grep can't tell a dedicated `body_html:` wrapper from a
# slot rendering bare into the root element. So #derive_parts walks each
# template's element/block nesting with a small stack: every element whose
# attributes come from a `**component.<part>_attributes` call pushes a
# frame recording that part (or ROOT_SHARED for `root_attributes`); every
# other opening construct -- a plain `do` block, an `<% if %>`/`<% unless
# %>`, a literal `<div>` -- pushes a frame recording nothing; `<% end %>`
# and `</div>` pop. When a line renders a slot's content (`<%= slots.body
# %>`, or the `tag.x(slots.body, **c.body_attributes)` single-tag idiom),
# the derivation walks the stack from the top down and reports the nearest
# frame that does carry a part -- exactly "what wraps this slot's content,
# skipping any wrapper that carries no hook at all", which is the same
# question a human answered by eye to write PARTS.
#
# #derive_parts also cross-checks every non-ROOT_SHARED answer against
# component.rb itself (via #hooked_parts): the part it found in the
# template must actually be one `html_for` exposes there, not just an
# ERB variable that happens to be named `..._attributes`.
RSpec.describe TablerUi::Docs::Editor::SlotParts do
  COMPONENTS_ROOT = File.expand_path("../../../../../app/components/tabler_ui", __dir__)

  ROOT_SHARED = described_class::ROOT_SHARED

  # Matches an opening construct that both starts a new nesting level AND
  # carries a part, e.g. `<%= tag.div(**card.body_attributes) do %>` or
  # `<%= tag.div(**modal.root_attributes(title_visible: x)) do %>`.
  BLOCK_OPEN_WITH_PART = /\*\*\w+\.(\w+)_attributes\b.*\bdo\b.*%>/

  # Matches an opening construct with no part of its own: a plain `do`
  # block (`capture do`, `array.each do |x|`, `tag.tr do`), or an `<% if
  # %>` / `<% unless %>` (deliberately NOT `<% elsif %>` -- an elsif
  # continues the same frame the `if` already pushed, rather than nesting
  # a new one).
  BLOCK_OPEN_PLAIN = /\bdo(?:\s*\|[^|]*\|)?\s*%>|\A\s*<%\s*(?:if|unless)\b/

  BLOCK_CLOSE = /<%\s*end\s*%>/

  # A literal HTML `<div ...>` that opens and closes on the same line (e.g.
  # `<div class="alert-description"><%= alert.text %></div>`) is net-zero
  # nesting -- must be checked, and skipped, before the plain open/close
  # patterns below, or it would be mistaken for an unmatched open.
  DIV_OPEN_CLOSE_SAME_LINE = %r{<div\b[^>]*>.*</div>}
  DIV_OPEN = /<div\b[^>]*>/
  DIV_CLOSE = %r{</div>}

  # The ordinary way a slot's content is emitted: `<%= slots.body %>` alone
  # on its output. Deliberately anchored to `<%=` (an output tag) so it
  # never matches a *guard*, e.g. `<% if defined?(slots) &&
  # slots.present?(:body) %>`, which contains the substring "slots.present"
  # but renders nothing and must not be mistaken for content.
  OUTPUT_SLOT_REF = /<%=\s*slots\.(\w+)\s*%>/

  # table's `footer` slot uses a different idiom -- the slot's content is
  # passed as the tag helper's own content argument, not a block body:
  # `tag.div(slots.footer, **table.footer_attributes)`. Handled separately
  # since it neither opens a stack frame nor matches OUTPUT_SLOT_REF.
  DIRECT_SLOT_WITH_PART = /tag\.\w+\(slots\.(\w+),\s*\*\*\w+\.(\w+)_attributes/

  # @param name [String] a captured part name, e.g. "body" or "root"
  # @return [Symbol] the part Symbol, translating "root" to ROOT_SHARED --
  #   a slot's content wrapped by the component's OWN root element (not a
  #   dedicated part of its own) is exactly the ROOT_SHARED case.
  def part_symbol(name)
    name == "root" ? ROOT_SHARED : name.to_sym
  end

  # Walks +path+'s ERB source and returns { slot_name => part_symbol } for
  # every `slots.<name>` this template renders, per the algorithm described
  # in this file's header comment.
  def derive_parts_from_template(path)
    stack = []
    results = {}

    File.readlines(path).each do |line|
      if (m = line.match(DIRECT_SLOT_WITH_PART))
        results[m[1]] ||= part_symbol(m[2])
      elsif (m = line.match(OUTPUT_SLOT_REF))
        nearest = stack.reverse.find { |frame| frame }
        results[m[1]] ||= nearest
      elsif line.match?(DIV_OPEN_CLOSE_SAME_LINE)
        # net-zero nesting -- deliberately no stack change
      elsif (m = line.match(BLOCK_OPEN_WITH_PART))
        stack.push(part_symbol(m[1]))
      elsif line.match?(BLOCK_OPEN_PLAIN)
        stack.push(nil)
      elsif line.match?(BLOCK_CLOSE)
        stack.pop
      elsif line.match?(DIV_OPEN)
        stack.push(nil)
      elsif line.match?(DIV_CLOSE)
        stack.pop
      end
    end

    results
  end

  # @param component [String]
  # @return [Array<Symbol>] every part component.rb actually exposes via
  #   `html_for(:part, ...)` -- used to cross-check that a part found in
  #   the template is genuinely hook-backed, not a same-named coincidence.
  def hooked_parts(component)
    source = File.read(File.join(COMPONENTS_ROOT, component, "component.rb"))
    source.scan(/html_for\(:(\w+)/).flatten.map(&:to_sym).uniq
  end

  def derive_parts(component)
    path = File.join(COMPONENTS_ROOT, component, "_component.html.erb")
    derive_parts_from_template(path)
  end

  describe "PARTS vs. the component sources -- the guard" do
    it "matches a fresh derivation from every slotted component's template" do
      TablerUi::Docs::Editor::SlotMap::SLOTS.each_key do |component|
        derived = derive_parts(component)

        expect(described_class::PARTS[component]).to eq(derived),
                                                        "expected #{component.inspect} slot parts to be " \
                                                        "#{derived.inspect}, got " \
                                                        "#{described_class::PARTS[component].inspect}"
      end
    end

    it "only ever maps a slot to a part component.rb actually exposes via html_for, or ROOT_SHARED" do
      described_class::PARTS.each do |component, slots|
        parts = hooked_parts(component)

        slots.each_value do |part|
          next if part == ROOT_SHARED

          expect(parts).to include(part),
                            "#{component.inspect}'s #{part.inspect} part has no matching " \
                            "html_for(:#{part}, ...) call in component.rb"
        end
      end
    end

    it "covers exactly the components SlotMap::SLOTS lists -- no more, no less" do
      expect(described_class::PARTS.keys.sort).to eq(TablerUi::Docs::Editor::SlotMap::SLOTS.keys.sort)
    end

    it "covers exactly the same slot names as SlotMap::SLOTS, per component" do
      TablerUi::Docs::Editor::SlotMap::SLOTS.each do |component, slots|
        expect(described_class::PARTS[component].keys.sort).to eq(slots.sort),
                                                                 "#{component.inspect}: PARTS lists " \
                                                                 "#{described_class::PARTS[component].keys.sort.inspect}, " \
                                                                 "SlotMap lists #{slots.sort.inspect}"
      end
    end

    it "fires when a dedicated part is mislabeled as root-shared (regression guard)" do
      # Proves the comparison actually catches drift instead of vacuously
      # passing -- mutates a duplicate, not the frozen constant.
      broken = described_class::PARTS.transform_values(&:dup)
      broken["card"]["body"] = ROOT_SHARED

      derived = derive_parts("card")

      expect(broken["card"]).not_to eq(derived)
    end

    it "fires when a root-shared slot is mislabeled with a fabricated dedicated part (regression guard)" do
      broken = described_class::PARTS.transform_values(&:dup)
      broken["alert"]["body"] = :body

      derived = derive_parts("alert")

      expect(broken["alert"]).not_to eq(derived)
    end

    it "fires when table's filter/filter_form mismatch is flattened to a same-name mapping (regression guard)" do
      broken = described_class::PARTS.transform_values(&:dup)
      broken["table"]["filter"] = :filter

      derived = derive_parts("table")

      expect(broken["table"]).not_to eq(derived)
    end
  end

  describe "PARTS" do
    it "is frozen, including every value hash" do
      expect(described_class::PARTS).to be_frozen

      described_class::PARTS.each_value do |slots|
        expect(slots).to be_frozen
      end
    end

    it "sorts component keys and, within each component, sorts slot names" do
      expect(described_class::PARTS.keys).to eq(described_class::PARTS.keys.sort)

      described_class::PARTS.each_value do |slots|
        expect(slots.keys).to eq(slots.keys.sort)
      end
    end
  end

  describe ".part_for" do
    it "returns the dedicated part for a clean 1:1 slot" do
      expect(described_class.part_for("card", "body")).to eq(:body)
    end

    it "returns ROOT_SHARED for a slot with no dedicated wrapper" do
      expect(described_class.part_for("alert", "body")).to eq(ROOT_SHARED)
    end

    it "returns the mismatched part for table's filter slot" do
      expect(described_class.part_for("table", "filter")).to eq(:filter_form)
    end

    it "accepts a Symbol as well as a String for both arguments" do
      expect(described_class.part_for(:card, :header)).to eq(:header)
    end

    it "returns UNMAPPED for a real component with no entry for the given slot" do
      expect(described_class.part_for("card", "not_a_slot")).to eq(described_class::UNMAPPED)
    end

    it "returns UNMAPPED for an unknown component, rather than raising" do
      expect(described_class.part_for("not_a_component", "body")).to eq(described_class::UNMAPPED)
    end
  end

  describe ".root_shared?" do
    it "is true for a root-shared slot" do
      expect(described_class.root_shared?("ribbon", "body")).to be(true)
    end

    it "is false for a dedicated-part slot" do
      expect(described_class.root_shared?("modal", "body")).to be(false)
    end

    it "is false for an unmapped pair" do
      expect(described_class.root_shared?("not_a_component", "body")).to be(false)
    end
  end
end
