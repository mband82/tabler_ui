# frozen_string_literal: true

require "nokogiri"

# Renders TablerUi components through the real dispatcher (TablerUi::Ui,
# see lib/tabler_ui/ui.rb) instead of stubbing anything, so specs exercise the
# same code path a host app's ERB templates use via `tabler_ui.<name>(...)`.
module ComponentHelper
  # Renders a component through the real dispatcher and returns the raw HTML
  # string.
  #
  # @param name [Symbol] component method name, e.g. :badge
  # @param args, kwargs, block forwarded to TablerUi::Ui#method_missing,
  #   exactly as they would be from `tabler_ui.badge(text: "Hello")` in ERB.
  # @return [String]
  def render_component(name, *args, **kwargs, &block)
    tabler_ui_view_context.tabler_ui.public_send(name, *args, **kwargs, &block)
  end

  # Same as #render_component, but parsed into a Nokogiri fragment so specs
  # can make CSS-selector assertions instead of matching raw strings.
  #
  # @return [Nokogiri::HTML5::DocumentFragment]
  def component_fragment(name, *args, **kwargs, &block)
    Nokogiri::HTML5.fragment(render_component(name, *args, **kwargs, &block))
  end

  private

  # Builds a real ActionView::Base view context wired up with the engine's
  # component view path and TablerUi::Helper (which is how `tabler_ui` becomes
  # available in real templates -- see lib/tabler_ui/engine.rb's
  # 'tabler_ui.helpers' initializer). A fresh context per example avoids any
  # state (e.g. memoized @tabler_ui) leaking between specs.
  def tabler_ui_view_context
    @tabler_ui_view_context ||= begin
      view_paths = ActionView::PathSet.new([TablerUi::Engine.root.join("app/components").to_s])
      view_class = ActionView::Base.with_empty_template_cache
      view_class.include(TablerUi::Helper)
      view_class.with_view_paths(view_paths, {})
    end
  end
end
