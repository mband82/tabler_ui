# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor/builder_map"
require "tabler_ui/docs/editor/builder_parts"

# BuilderParts::PARTS is hand-maintained (see its module doc for why -- same
# reason as SlotParts/BuilderMap: docs/lib is not autoloaded or reloaded, so
# deriving it at load time would only ever reflect server-boot state
# anyway). This spec re-derives the truth fresh, at runtime, straight from
# the real component sources, in two steps mirroring SlotParts' own spec:
#
#   1. #derive_internal_part walks a template's element/block nesting (the
#      same small-stack algorithm slot_parts_spec.rb uses, keyed to a
#      builder item's own content capture -- `capture(&item.content)`,
#      `capture(&item[:block])`, or the bare `<%= item[:content] %>`
#      fallback -- instead of `slots.<name>`) to find which internal part
#      (:item_body, :card, :pane, :item, :content, ...) wraps that content.
#   2. #derive_outward_part reads component.rb to translate that internal
#      part into the OUTWARD `<x>_html:` kwarg name a caller actually
#      writes (accordion's :item_body -> :body, because
#      `@tabler_ui_html_options[:item_body] = item.body_html` is the line
#      that resolves it) -- or COMPONENT_LEVEL when no such per-item
#      reassignment exists anywhere in the file (datagrid's :content, whose
#      hook is only ever set once at construction, never per #item call).
RSpec.describe TablerUi::Docs::Editor::BuilderParts do
  COMPONENTS_ROOT = File.expand_path("../../../../../app/components/tabler_ui", __dir__)

  COMPONENT_LEVEL = described_class::COMPONENT_LEVEL

  # A builder item's own content, in one of the three idioms the six
  # `block: :children` templates actually use: `capture(&item.content)` /
  # `capture(&item[:block])` (accordion/carousel/timeline/tabs/
  # settings_page, datagrid's own block form), or the bare `item[:content]`
  # output (datagrid's non-block fallback). Deliberately NOT anchored to a
  # specific variable name ("item"/"tab") -- both appear across these six
  # templates.
  CONTENT_REF = /capture\(&\w+(?:\.content|\[:block\])\)|<%=\s*\w+\[:content\]\s*%>/

  # An opening construct that both starts a new nesting level AND carries a
  # part -- e.g. `<%= tag.div(**accordion.item_body_attributes(item)) do %>`
  # or `<%= tag.div(id: item.id, **settings_page.pane_attributes(item)) do %>`.
  # Requires the accessor's own argument (`item`/`tab`) so a component-level
  # accessor taking no argument at all (`tabs.content_attributes`, called
  # with no parens) never matches -- exactly the exclusion that keeps a
  # component-level wrapper out of the per-item part vocabulary this spec
  # derives.
  BLOCK_OPEN_WITH_PART = /\*\*\w+\.(\w+)_attributes\(\w+\).*\bdo\b.*%>/

  # A plain opening construct with no part of its own: a `do`/`do |x|`
  # block, or an `<% if %>`/`<% unless %>` -- deliberately NOT `<% elsif
  # %>`/`<% else %>`, both of which continue the SAME frame the `if`
  # already pushed rather than nesting a new one (mirrors
  # slot_parts_spec.rb's own BLOCK_OPEN_PLAIN exactly).
  BLOCK_OPEN_PLAIN = /\bdo(?:\s*\|[^|]*\|)?\s*%>|\A\s*<%\s*(?:if|unless)\b/

  BLOCK_CLOSE = /<%\s*end\s*%>/

  DIV_OPEN_CLOSE_SAME_LINE = %r{<div\b[^>]*>.*</div>}
  DIV_OPEN = /<div\b[^>]*>/
  DIV_CLOSE = %r{</div>}

  # @return [Array<Array(String, String)>] every (component, method) pair
  #   BuilderMap records with `block: :children`, across every level (only
  #   :root has one today, but this walks generically rather than assuming
  #   that stays true).
  def block_children_pairs
    pairs = []
    TablerUi::Docs::Editor::BuilderMap::BUILDERS.each do |component, levels|
      levels.each_value do |methods|
        methods.each do |method_name, descriptor|
          pairs << [component, method_name] if descriptor[:block] == :children
        end
      end
    end
    pairs
  end

  # Walks +path+'s ERB source with a small stack, same algorithm
  # slot_parts_spec.rb's #derive_parts_from_template uses -- see that
  # file's header for the full walk description. Returns the nearest
  # part-carrying frame open at the point the item's own content is
  # referenced, or nil if no CONTENT_REF line is found at all.
  def derive_internal_part(template_path)
    stack = []

    File.readlines(template_path).each do |line|
      if line.match?(CONTENT_REF)
        return stack.reverse.find { |frame| frame }
      elsif line.match?(DIV_OPEN_CLOSE_SAME_LINE)
        # net-zero nesting -- deliberately no stack change
      elsif (m = line.match(BLOCK_OPEN_WITH_PART))
        stack.push(m[1].to_sym)
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

    nil
  end

  # @param component [String]
  # @param internal_part [Symbol] the part #derive_internal_part found
  #   (e.g. :item_body, :card, :pane, :item)
  # @return [Symbol] the outward `<x>_html:` kwarg name (as used at the
  #   design/call site, e.g. :body for :item_body's `body_html:`), :root
  #   for the literal `.html` field, or COMPONENT_LEVEL if component.rb
  #   never reassigns `@tabler_ui_html_options[:<internal_part>]` anywhere
  #   -- i.e. that part is only ever set once, at construction, never per
  #   builder-item call.
  def derive_outward_part(component, internal_part)
    return COMPONENT_LEVEL if internal_part.nil?

    source = File.read(File.join(COMPONENTS_ROOT, component, "component.rb"))
    m = source.match(/@tabler_ui_html_options\[:#{internal_part}\]\s*=\s*\w+\.(\w+)/)
    return COMPONENT_LEVEL unless m

    key = m[1]
    key == "html" ? :root : key.delete_suffix("_html").to_sym
  end

  def derive_part(component, method)
    template_path = File.join(COMPONENTS_ROOT, component, "_component.html.erb")
    internal_part = derive_internal_part(template_path)
    derive_outward_part(component, internal_part)
  end

  describe "PARTS vs. the component sources -- the guard" do
    it "matches a fresh derivation for every block: :children pair BuilderMap records" do
      block_children_pairs.each do |component, method|
        derived = derive_part(component, method)

        expect(described_class::PARTS.dig(component, method)).to eq(derived),
                                                                   "expected #{component.inspect}##{method.inspect} " \
                                                                   "to derive #{derived.inspect}, got " \
                                                                   "#{described_class::PARTS.dig(component, method).inspect}"
      end
    end

    it "covers exactly the (component, method) pairs BuilderMap marks block: :children -- no more, no less" do
      registered = described_class::PARTS.flat_map { |component, methods| methods.keys.map { |m| [component, m] } }

      expect(registered.sort).to eq(block_children_pairs.sort)
    end

    it "only ever maps a per-item part to an html_for part actually reassigned per-item in component.rb" do
      described_class::PARTS.each do |component, methods|
        methods.each_value do |part|
          next if [described_class::COMPONENT_LEVEL, :root].include?(part)

          source = File.read(File.join(COMPONENTS_ROOT, component, "component.rb"))
          expect(source).to match(/=\s*\w+\.#{part}_html\b/),
                             "#{component.inspect}'s #{part.inspect} part has no matching " \
                             "per-item `<var>.#{part}_html` reassignment in component.rb"
        end
      end
    end

    it "fires when a per-item part is mislabeled as COMPONENT_LEVEL (regression guard)" do
      broken = described_class::PARTS.transform_values(&:dup)
      broken["accordion"]["item"] = COMPONENT_LEVEL

      derived = derive_part("accordion", "item")

      expect(broken["accordion"]["item"]).not_to eq(derived)
    end

    it "fires when COMPONENT_LEVEL is mislabeled as a fabricated per-item part (regression guard)" do
      broken = described_class::PARTS.transform_values(&:dup)
      broken["datagrid"]["item"] = :content

      derived = derive_part("datagrid", "item")

      expect(broken["datagrid"]["item"]).not_to eq(derived)
    end

    it "fires when carousel's :root is mislabeled as a fabricated dedicated part (regression guard)" do
      broken = described_class::PARTS.transform_values(&:dup)
      broken["carousel"]["item"] = :caption

      derived = derive_part("carousel", "item")

      expect(broken["carousel"]["item"]).not_to eq(derived)
    end
  end

  describe "PARTS" do
    it "is frozen, including every value hash" do
      expect(described_class::PARTS).to be_frozen

      described_class::PARTS.each_value do |methods|
        expect(methods).to be_frozen
      end
    end

    it "sorts component keys" do
      expect(described_class::PARTS.keys).to eq(described_class::PARTS.keys.sort)
    end
  end

  describe ".part_for" do
    it "returns the outward part for a per-item hook" do
      expect(described_class.part_for("accordion", "item")).to eq(:body)
    end

    it "returns :root for carousel's item, whose own root is its content wrapper" do
      expect(described_class.part_for("carousel", "item")).to eq(:root)
    end

    it "returns COMPONENT_LEVEL for datagrid's item" do
      expect(described_class.part_for("datagrid", "item")).to eq(COMPONENT_LEVEL)
    end

    it "accepts a Symbol as well as a String for both arguments" do
      expect(described_class.part_for(:tabs, :tab)).to eq(:pane)
    end

    it "returns UNMAPPED for a real component with no entry for the given method" do
      expect(described_class.part_for("accordion", "not_a_method")).to eq(described_class::UNMAPPED)
    end

    it "returns UNMAPPED for an unknown component, rather than raising" do
      expect(described_class.part_for("not_a_component", "item")).to eq(described_class::UNMAPPED)
    end
  end

  describe ".component_level?" do
    it "is true for datagrid's item" do
      expect(described_class.component_level?("datagrid", "item")).to be(true)
    end

    it "is false for a per-item hook" do
      expect(described_class.component_level?("timeline", "item")).to be(false)
    end

    it "is false for an unmapped pair" do
      expect(described_class.component_level?("not_a_component", "item")).to be(false)
    end
  end
end
