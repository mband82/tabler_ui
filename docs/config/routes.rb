# frozen_string_literal: true

TablerUi::Docs::Engine.routes.draw do
  root to: "pages#home"

  # Proves the demo mechanism (DemoRegistry + docs/app/views/tabler_ui/docs/demos/_demo.html.erb)
  # is reachable through the mounted engine -- see DemosController. Real
  # per-component navigation is other agents' work.
  get "demos/:component", to: "demos#show", as: :component_demos

  # Backing endpoint for the table component's one genuinely stateful demo
  # (docs/lib/tabler_ui/docs/demos/table_demos.rb, :sort_filter_page) --
  # sorting/filtering/paging happen here, server-side, exactly like
  # showcase/app/controllers/showcase_controller.rb's #layout action did for
  # the old showcase's "table - frame:" example. Named explicitly (`as:
  # :table_demo`) rather than left to route the demo's ERB could plausibly
  # print as sample code, so it's obviously scoped to this one demo and not
  # mistakable for a route a reader's own app would have. See
  # TableDemoController for why this exists as a real routed endpoint rather
  # than being expressed purely through Demo#locals.
  get "table_demo", to: "table_demo#show", as: :table_demo

  # Forms harness: wraps every form_builder_demos.rb demo in one real
  # tabler_form_with around a TablerUi::Docs::PersonForm, so
  # f.error_notification / inline validation errors render as they would in
  # a host app -- unlike demos/:component, whose fragments render standalone
  # (each with its own throwaway f). See FormsController.
  get "forms", to: "forms#show", as: :forms

  # The real per-component documentation page: generated API reference
  # (TablerUi::Docs::DocParser) plus the curated live-demo corpus
  # (TablerUi::Docs::DemoRegistry) for one component, side by side. See
  # ComponentsController. This is what the sidebar (rendered on every docs
  # page, see the application layout) links every component name to.
  get "components/:name", to: "components#show", as: :component

  # Full-text search index: GET /ui/search returns every
  # TablerUi::Docs::SearchIndex entry as JSON, fetched once by the
  # tabler-ui--docs-search Stimulus controller and filtered entirely
  # client-side -- see docs/lib/tabler_ui/docs/search_index.rb and
  # docs/app/javascript/controllers/tabler_ui/docs/search_controller.js.
  get "search", to: "search#index", as: :search
end
