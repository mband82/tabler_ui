# frozen_string_literal: true

require "rails_helper"
require "tabler_ui/docs/editor/renderer"
require "tabler_ui/docs/editor/slot_map"
require "tabler_ui/docs/editor/slot_parts"

# The anti-rot check for Renderer's `decorate:` flag (design-editor
# "layout guide" markup, see Renderer's own "Decoration" class docs). The
# guarantee this file exists to hold the line on: decorated output is
# undecorated output plus EXACTLY the deltas SlotParts declares for that
# component's slots -- nothing extra anywhere else in the tree, and nothing
# missing where SlotParts says a marker belongs. Every expectation below is
# computed FROM SlotMap/SlotParts for the component under test, not
# hardcoded per component -- a change to either registry (or to which
# components/slots exist at all) changes what this spec expects without
# anyone having to edit this file.
#
# `type: :component` pulls in spec/support/component_helper.rb's
# #tabler_ui_view_context (config.include ComponentHelper, type: :component
# in spec/rails_helper.rb), the same real ActionView::Base + TablerUi::Helper
# wiring renderer_spec.rb already renders through.
RSpec.describe "Renderer decoration (layout guides)", type: :component do
  SlotMap = TablerUi::Docs::Editor::SlotMap
  SlotParts = TablerUi::Docs::Editor::SlotParts

  let(:view) { tabler_ui_view_context }

  def renderer(decorate:)
    TablerUi::Docs::Editor::Renderer.new(view, decorate: decorate)
  end

  def frag(html)
    Nokogiri::HTML5.fragment(html.to_s)
  end

  # --- Contract-shaped node builders (mirrors renderer_spec.rb's own) ------

  def component_node(name, id, args: {}, options: {}, slots: nil)
    node = { "kind" => "component", "id" => id, "name" => name, "args" => args, "options" => options, "html" => {} }
    node["slots"] = slots if slots
    node
  end

  def text_node(id, content:)
    { "kind" => "text", "id" => id, "tag" => "p", "content" => content }
  end

  # The 2 of SlotMap's 13 components with a mandatory positional.
  REQUIRED_ARGS = {
    "modal" => { "id" => "modal-x" },
    "offcanvas" => { "id" => "off-x" }
  }.freeze

  # Per-component options needed for a sane, non-erroring render -- every
  # other one of the 13 renders fine from bare defaults (renderer_spec.rb's
  # own 35-component sweep already proves that for the whole component
  # set). `table` needs a `filter:` truthy Hash with no `fields:` so its
  # `filter` slot is eligible for decoration in this generic sweep at all
  # -- table's own veto logic (filter: absent, and filter: with fields:)
  # gets its own dedicated examples further down, deliberately OUTSIDE this
  # generic per-component loop. `avatar` needs `image:` so its ROOT_SHARED
  # `overlay` slot doesn't trip the identicon-mode guard when the "filled"
  # variant puts real content there -- that guard, and decoration's
  # interaction with it, also gets its own dedicated example below.
  DEFAULT_OPTIONS = {
    "avatar" => { "image" => "https://example.com/avatar.png" },
    "table" => { "filter" => { "url" => "/people" } }
  }.freeze

  # @param filled [Boolean] false builds every SlotMap-known slot for this
  #   component as an explicitly-empty entry (mirrors Tree's own shape for
  #   "the slot key was never touched" -- see tree.rb#normalize_slots);
  #   true builds every one with one real text child.
  def slot_variant_node(component, id, filled:)
    slot_names = SlotMap.slots_for(component)
    slots = slot_names.each_with_object({}) do |slot, acc|
      acc[slot] = filled ? [text_node("#{id}-#{slot}-t", content: "#{slot} content")] : []
    end

    component_node(component, id,
                    args: REQUIRED_ARGS.fetch(component, {}),
                    options: DEFAULT_OPTIONS.fetch(component, {}),
                    slots: slots)
  end

  # --- Structural comparison: decorated == undecorated + declared deltas --
  #
  # Decoration only ever ADDS (see the class docs -- attributes merged into
  # already-symbolized opts, content added to an otherwise-untouched
  # SlotContext); it never removes or reorders anything the undecorated
  # render already produces. So rather than trying to independently
  # canonicalize each render and compare the results for equality (which
  # cannot tell "the decorated wrapper is a legitimate new delta" apart
  # from "the decorated wrapper is a bug" without already knowing, per
  # component, which wrappers are gated on slot presence and which -- like
  # dimmer's, uniquely among these 13 -- always render regardless), this
  # walks BOTH trees together: every node the undecorated tree has must
  # appear, in order, in the decorated tree (#nodes_equal?); anything
  # decorated has IN BETWEEN those matches is only acceptable
  # (#valid_insertion?) if its entire subtree is decoration's own doing --
  # a placeholder, or plain structural markup (nothing but a `class`
  # attribute, e.g. page_header's `.btn-list` wrapper around its
  # placeholder) wrapping nothing but more of the same.

  # `data-editor-node-id` is stripped everywhere, not just on a slot's own
  # wrapper -- it is already identical between the two renders wherever it
  # existed before decoration (same node, same id), and decoration adds it
  # fresh to a slot wrapper that didn't carry one at all undecorated. This
  # spec's whole job is what SlotParts adds/where -- not re-proving
  # `data-editor-node-id` stamping is correct, which renderer_spec.rb
  # already covers in full.
  DECORATION_ATTRS = %w[data-editor-slot data-editor-slot-shared data-editor-node-id].freeze

  # A synthesized empty-slot placeholder (Renderer#editor_slot_placeholder):
  # a bare <div> with no class, no text, aria-hidden="true", and nothing
  # else but the marker attrs. Identified structurally, not by position,
  # since which slots get one varies per component/variant.
  def placeholder_element?(node)
    return false unless node.is_a?(Nokogiri::XML::Element) && node.name == "div"
    return false unless node["aria-hidden"] == "true"
    return false unless node["class"].nil?
    return false unless node.children.all? { |c| c.text? && c.text.strip.empty? }

    extra_attrs = node.attribute_nodes.map(&:name) - %w[data-editor-slot data-editor-node-id aria-hidden]
    extra_attrs.empty?
  end

  # Canonicalizes one HTML fragment into a plain nested Array/Hash
  # structure -- a placeholder becomes the `:placeholder` sentinel (never a
  # Hash, so it can never accidentally satisfy #nodes_equal? against a real
  # undecorated node), every other element keeps its tag/attrs (decoration
  # attrs stripped -- see DECORATION_ATTRS) and canonicalized children.
  # Lenient about whitespace-only text, matching consistency_spec.rb's own
  # `canonicalize_node` (independently duplicated here, not shared, per
  # this codebase's convention of each editor spec file owning its own
  # node/comparison helpers).
  def canonicalize_node(node)
    case node
    when Nokogiri::XML::Element
      return :placeholder if placeholder_element?(node)

      attrs = node.attributes.each_with_object({}) do |(name, attr), acc|
        acc[name] = attr.value unless DECORATION_ATTRS.include?(name)
      end
      { tag: node.name, attrs: attrs, children: node.children.filter_map { |c| canonicalize_node(c) } }
    when Nokogiri::XML::Text, Nokogiri::XML::CDATA
      text = node.text.gsub(/\s+/, " ").strip
      text.empty? ? nil : { text: text }
    end
  end

  def canonicalize(html)
    Nokogiri::HTML5.fragment(html.to_s).children.filter_map { |c| canonicalize_node(c) }
  end

  # @return [Boolean] whether `node` (and everything inside it) could only
  #   be decoration's own doing: the placeholder sentinel itself, or an
  #   element with no attribute but `class` whose children are themselves
  #   entirely valid insertions all the way down. Real content (text, or
  #   an element with an id/data/aria/etc. attribute of its own) can never
  #   satisfy this, so an unexpected insertion elsewhere in the tree still
  #   fails the comparison instead of being silently waved through.
  def valid_insertion?(node)
    return true if node == :placeholder
    return false unless node.is_a?(Hash) && node.key?(:tag)
    return false unless (node[:attrs].keys - ["class"]).empty?

    node[:children].all? { |child| valid_insertion?(child) }
  end

  # @return [Boolean] whether `expected` and `actual` are the same node --
  #   text nodes by plain equality, elements by tag + (decoration-attr-
  #   stripped) attrs + their children satisfying #children_align?.
  def nodes_equal?(expected, actual)
    return false if [expected, actual].include?(:placeholder)
    return expected == actual if expected.is_a?(Hash) && expected.key?(:text)

    expected.is_a?(Hash) && actual.is_a?(Hash) && expected[:tag] == actual[:tag] &&
      expected[:attrs] == actual[:attrs] && children_align?(expected[:children], actual[:children])
  end

  # @return [Boolean] whether every one of `expected`'s nodes, in order,
  #   has a match somewhere in `actual` -- anything in `actual` that isn't
  #   part of a match must be a #valid_insertion? (decoration's own
  #   placeholder/wrapper markup) or this fails. This is the "decorated ==
  #   undecorated + only declared deltas" check applied at every level of
  #   the tree, not just the top.
  def children_align?(expected, actual)
    ei = 0
    actual.each do |node|
      if ei < expected.length && nodes_equal?(expected[ei], node)
        ei += 1
      else
        return false unless valid_insertion?(node)
      end
    end
    ei == expected.length
  end

  # --- Positive, per-slot marker assertions, derived from SlotParts -------

  # @return [Integer] how many elements decorated output should carry
  #   `data-editor-slot="<slot>"` for a PRECISE (non-ROOT_SHARED) slot: the
  #   dedicated wrapper always gets one (marker stamping runs regardless of
  #   content, see Renderer#decorate_slot_opts); an EMPTY slot additionally
  #   gets a placeholder child carrying the same attribute, so 2 -- unless
  #   Renderer#decorated_placeholder_allowed? vetoes the placeholder for
  #   this exact (component, slot) under DEFAULT_OPTIONS. table's slots are
  #   excluded from this generic sweep entirely (own examples below cover
  #   its two veto cases); the one other veto DEFAULT_OPTIONS' blank
  #   options actually trigger is offcanvas's `header`, whose
  #   `close_button:` defaults to true (see
  #   Renderer::FALLBACK_GUARDED_SLOTS) -- every other guarded slot
  #   (card/modal/toast `header`, empty's `img`/`icon`/`header`) needs a
  #   `title:`/`image:`/`icon:`/`header:` option this sweep never sets, so
  #   stays un-vetoed here and gets its own coverage in the "non-
  #   vacuousness"/fallback-guard examples below instead.
  def expected_precise_marker_count(component, slot, filled)
    return 1 if filled
    return 1 if component == "offcanvas" && slot == "header"

    2
  end

  describe "every SlotMap component" do
    SlotMap::SLOTS.each_key do |component|
      context component do
        [true, false].each do |filled|
          it "#{filled ? 'filled' : 'empty'} slots: decorated equals undecorated plus exactly SlotParts' deltas" do
            node = slot_variant_node(component, "n-#{component}", filled: filled)

            undecorated_html = renderer(decorate: false).render(node).to_s
            decorated_html = renderer(decorate: true).render(node).to_s

            expect(decorated_html).not_to include("alert alert-danger"),
                                            "decoration errored where the undecorated render did not:\n#{decorated_html}"

            # Structural equivalence: every undecorated node still appears,
            # in order, inside the decorated tree, and everything decorated
            # adds beyond that is decoration's own placeholder/wrapper
            # markup -- nothing else diverges anywhere in the tree.
            undecorated_canon = canonicalize(undecorated_html)
            decorated_canon = canonicalize(decorated_html)
            expect(children_align?(undecorated_canon, decorated_canon)).to be(true),
              "decorated output diverges from undecorated by more than SlotParts' declared markers for " \
              "'#{component}' (filled: #{filled})\n\nundecorated:\n#{undecorated_html}\n\ndecorated:\n#{decorated_html}"

            # Positive check: SlotParts' declared marker actually landed,
            # for every one of this component's slots, not merely "nothing
            # ELSE changed" (which a no-op decoration would also satisfy).
            doc = frag(decorated_html)
            SlotMap.slots_for(component).each do |slot|
              if SlotParts.root_shared?(component, slot)
                shared = doc.css("[data-editor-slot-shared]").map { |el| el["data-editor-slot-shared"] }
                expect(shared.any? { |value| value.split(",").include?(slot) }).to be(true),
                  "expected some element to carry data-editor-slot-shared including '#{slot}' for '#{component}'"
              else
                matches = doc.css(%([data-editor-slot="#{slot}"]))
                expected = expected_precise_marker_count(component, slot, filled)
                expect(matches.size).to eq(expected),
                  "expected #{expected} element(s) marked data-editor-slot=\"#{slot}\" " \
                  "for '#{component}' (filled: #{filled}), got #{matches.size}"
              end
            end
          end
        end
      end
    end
  end

  # --- Non-vacuousness: decoration really does add something concrete -----

  describe "non-vacuousness" do
    it "an empty card gains real wrapper elements and placeholders it would not otherwise render at all" do
      node = component_node("card", "card1", options: { "title" => "" })

      undecorated = renderer(decorate: false).render(node).to_s
      decorated = renderer(decorate: true).render(node).to_s

      # Undecorated: no header/body/footer wrapper at all -- title is blank
      # and no slot was ever touched, so the template's own
      # `slots.present?(:x)` gates every one of them out.
      expect(undecorated).not_to include("card-body")
      expect(undecorated).not_to include("card-footer")

      # Decorated: all three wrappers now exist, each carrying its own
      # SlotParts-mapped marker, each holding an inert placeholder.
      doc = frag(decorated)
      %w[header body footer].each do |slot|
        wrapper = doc.at_css(".card-#{slot}")
        expect(wrapper).not_to be_nil, "expected a .card-#{slot} wrapper under decoration"
        expect(wrapper["data-editor-slot"]).to eq(slot)
        expect(wrapper["data-editor-node-id"]).to eq("card1")

        placeholder = wrapper.at_css("div[aria-hidden='true']")
        expect(placeholder).not_to be_nil, "expected an inert placeholder inside .card-#{slot}"
        expect(placeholder["class"]).to be_nil
        expect(placeholder.text.strip).to eq("")
        expect(placeholder["data-editor-slot"]).to eq(slot)
      end
    end

    it "an empty ribbon (ROOT_SHARED body) gains the coarse marker on its own root, and no placeholder" do
      node = component_node("ribbon", "rib1", options: { "text" => "" })

      decorated = renderer(decorate: true).render(node).to_s
      doc = frag(decorated)

      root = doc.at_css('[data-editor-node-id="rib1"]')
      expect(root["data-editor-slot-shared"]).to eq("body")
      expect(doc.at_css("div[aria-hidden='true']")).to be_nil
    end
  end

  # --- table's filter slot: the two veto cases -----------------------------

  describe "table's filter slot" do
    def table_node(id, filter_option:)
      options = { "columns" => [{ "label" => "Name", "key" => "name" }], "data" => [] }
      options["filter"] = filter_option if filter_option
      component_node("table", id, options: options, slots: { "filter" => [], "footer" => [] })
    end

    it "adds no filter marker/placeholder at all when filter: was never given -- " \
       "the component's own gating never renders that wrapper either way" do
      node = table_node("t1", filter_option: nil)

      decorated = renderer(decorate: true).render(node).to_s
      expect(decorated).not_to include("data-editor-slot=\"filter\"")
      expect(frag(decorated).css("form")).to be_empty
    end

    it "marks the real declarative-fields form but adds no placeholder when filter: carries fields:" do
      node = table_node("t2", filter_option: { "url" => "/people", "fields" => [{ "name" => "q" }] })

      decorated = renderer(decorate: true).render(node).to_s
      doc = frag(decorated)

      form = doc.at_css("form")
      expect(form).not_to be_nil
      expect(form["data-editor-slot"]).to eq("filter")
      # The real fields: form (an <input name="q">), not a placeholder --
      # exactly one match for the marker, no synthesized second element.
      expect(doc.css('[data-editor-slot="filter"]').size).to eq(1)
      expect(doc.at_css('input[name="q"]')).not_to be_nil
    end

    it "marks the wrapper AND adds a placeholder when filter: has no fields: and no slot content" \
       " -- the ordinary empty-slot case" do
      node = table_node("t3", filter_option: { "url" => "/people" })

      decorated = renderer(decorate: true).render(node).to_s
      doc = frag(decorated)

      expect(doc.css('[data-editor-slot="filter"]').size).to eq(2)
    end
  end

  # --- avatar's overlay slot: ROOT_SHARED means no synthesized placeholder,
  #     so decoration cannot ITSELF trigger the identicon-mode guard; real
  #     slot content still can, exactly as it already could undecorated ----

  describe "avatar's overlay slot" do
    it "decorating a fully-empty identicon avatar (no image:/initials:) does not raise -- " \
       "ROOT_SHARED means overlay never gets a synthesized placeholder to trip the guard with" do
      node = component_node("avatar", "av1", slots: { "overlay" => [] })

      decorated = nil
      expect { decorated = renderer(decorate: true).render(node).to_s }.not_to raise_error
      expect(decorated).not_to include("alert alert-danger")
    end

    it "real overlay content on an identicon avatar still raises, decorated or not -- " \
       "pre-existing Avatar::Component behaviour, isolated to one error marker by Renderer#render_node " \
       "exactly the same both ways" do
      node = component_node("avatar", "av2", slots: { "overlay" => [text_node("ov", content: "x")] })

      [false, true].each do |decorate|
        html = renderer(decorate: decorate).render(node).to_s
        doc = frag(html)
        marker = doc.at_css('[data-editor-node-id="av2"]')

        expect(marker["class"]).to eq("alert alert-danger")
        expect(marker.text).to include("overlay")
      end
    end
  end

  # --- The other 7 fallback-guarded slots (Renderer::FALLBACK_GUARDED_SLOTS)
  #
  # Found the same way the task description said to verify table/avatar
  # rather than trust it: reading every one of the 13 templates. card,
  # modal, toast and offcanvas's `header`, and empty's `img`/`icon`/
  # `header`, don't gate their wrapper on slot-presence alone -- they
  # branch between real fallback content (a title, an illustration, an
  # icon, plain text) and the slot. A placeholder must never win that
  # branch over real, already-visible content -- see
  # Renderer::FALLBACK_GUARDED_SLOTS' own doc for the full argument and
  # offcanvas's own extra `close_button:` wrinkle.

  describe "fallback-guarded slots" do
    # Only the SLOT UNDER TEST's own guard is at stake in each example
    # below -- card/modal/offcanvas also have body/footer slots, and
    # empty also has an unguarded `action` slot, left untouched (so
    # genuinely empty) by every node here on purpose; those correctly
    # DO still get their own ordinary placeholders (proven by the generic
    # sweep above), so assertions here are scoped to the guarded slot's
    # own wrapper, not "no placeholder anywhere in the whole component".
    it "does not clobber a real card title with a placeholder" do
      node = component_node("card", "card2", options: { "title" => "My Card" }, slots: { "header" => [] })

      decorated = renderer(decorate: true).render(node).to_s
      doc = frag(decorated)

      expect(doc.at_css(".card-title")&.text).to eq("My Card")
      expect(doc.at_css(".card-header div[aria-hidden='true']")).to be_nil
      expect(doc.at_css(".card-header")["data-editor-slot"]).to eq("header")
    end

    it "does not clobber a real modal title with a placeholder" do
      node = component_node("modal", "modal1", args: { "id" => "m1" },
                                                options: { "title" => "Confirm" }, slots: { "header" => [] })

      decorated = renderer(decorate: true).render(node).to_s
      doc = frag(decorated)

      expect(doc.at_css(".modal-title")&.text).to eq("Confirm")
      expect(doc.at_css(".modal-header div[aria-hidden='true']")).to be_nil
    end

    it "does not clobber a real toast title with a placeholder" do
      node = component_node("toast", "toast1", options: { "title" => "Saved" }, slots: { "header" => [] })

      decorated = renderer(decorate: true).render(node).to_s
      doc = frag(decorated)

      expect(doc.at_css("strong")&.text).to eq("Saved")
      expect(doc.at_css(".toast-header div[aria-hidden='true']")).to be_nil
    end

    it "does not clobber offcanvas's default close button (close_button: true, the default) with a " \
       "placeholder -- the regression this guard exists for" do
      node = component_node("offcanvas", "off1", args: { "id" => "o1" }, slots: { "header" => [] })

      decorated = renderer(decorate: true).render(node).to_s
      doc = frag(decorated)

      expect(doc.at_css("button.btn-close")).not_to be_nil
      expect(doc.at_css(".offcanvas-header div[aria-hidden='true']")).to be_nil
      expect(doc.at_css(".offcanvas-header")["data-editor-slot"]).to eq("header")
    end

    it "DOES synthesize a placeholder for offcanvas's header once close_button: false removes the last fallback" do
      node = component_node("offcanvas", "off2", args: { "id" => "o2" },
                                                   options: { "close_button" => false }, slots: { "header" => [] })

      decorated = renderer(decorate: true).render(node).to_s
      doc = frag(decorated)

      expect(doc.at_css("button.btn-close")).to be_nil
      expect(doc.at_css(".offcanvas-header div[aria-hidden='true']")).not_to be_nil
    end

    it "does not clobber empty's real image/icon/header fallbacks with placeholders" do
      node = component_node("empty", "empty1",
                            options: { "image" => "photos", "icon" => "alert-circle", "header" => "No data" },
                            slots: { "img" => [], "icon" => [], "header" => [] })

      decorated = renderer(decorate: true).render(node).to_s
      doc = frag(decorated)

      expect(doc.at_css(".empty-header")&.text&.strip).to eq("No data")
      %w[img icon header].each do |slot|
        expect(doc.at_css(".empty-#{slot} div[aria-hidden='true']")).to be_nil
        expect(doc.css(%([data-editor-slot="#{slot}"])).size).to eq(1)
      end
    end
  end
end
