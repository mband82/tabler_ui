# frozen_string_literal: true

require "rails_helper"

# The overlays components (modal, offcanvas, toast, carousel -- see
# docs/lib/tabler_ui/docs/demos/{modal,offcanvas,toast,carousel}_demos.rb)
# carry DOM ids: data-bs-toggle="modal" data-bs-target="#demo-modal" and the
# matching tabler_ui.modal "demo-modal". Bootstrap resolves data-bs-target
# document-wide, and docs/app/controllers/tabler_ui/docs/demos_controller.rb
# (GET /ui/demos/:component) renders every registered demo for one component
# on a single page. If two demos for the same component ever reused an id,
# the first element in the DOM would win and the second trigger would open
# (or show) the wrong dialog/panel/toast/slide -- silently, since nothing
# else here would fail. This spec renders every demo for each component that
# has any, on one page each (mirroring what the demos controller actually
# does), and asserts no id= attribute repeats.
RSpec.describe "Demo DOM id uniqueness" do
  def demo_view_context
    view_paths = ActionView::PathSet.new([TablerUi::Engine.root.join("app/components").to_s])
    view_class = ActionView::Base.with_empty_template_cache
    view_class.include(TablerUi::Helper)
    view_class.with_view_paths(view_paths, {})
  end

  TablerUi::Docs::DemoRegistry.components.each do |component|
    it "renders every #{component} demo together with no duplicate id= attribute" do
      view = demo_view_context

      html = TablerUi::Docs::DemoRegistry.for(component).map do |demo|
        view.render(inline: demo.source, locals: demo.resolved_locals)
      end.join("\n")

      ids = html.scan(/\bid="([^"]+)"/).flatten
      duplicates = ids.tally.select { |_, count| count > 1 }.keys

      expect(duplicates).to be_empty, "duplicate id(s) #{duplicates.inspect} found rendering all :#{component} demos together"
    end
  end
end
