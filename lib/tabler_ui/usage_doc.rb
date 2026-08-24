# frozen_string_literal: true

# TablerUi::Docs::Navigation, ::DocParser and ::DemoRegistry live under
# docs/lib/tabler_ui/docs/*.rb, which is on $LOAD_PATH (see the gemspec's
# require_paths) but NOT Zeitwerk-autoloaded, and docs.rb itself only
# requires engine/demo/demo_registry at gem-boot time (see that file's own
# comment) -- Navigation and DocParser are left to whichever caller needs
# them, the same way docs/app/controllers/tabler_ui/docs/application_controller.rb
# requires them for the live docs engine's controllers. This module is the
# equivalent entry point for the Rake task.
require "tabler_ui/docs/navigation"
require "tabler_ui/docs/doc_parser"

module TablerUi
  # Generates USAGE.md at the repo root: the exhaustive alternative to
  # README.md, which documents ~7 of the 19 (really 35) components and has
  # drifted stale (see CLAUDE.md's Gotchas section). Sourced from the exact
  # same doc-comment/demo data the live docs engine (mounted from docs/)
  # renders -- TablerUi::Docs::DocParser's parse of each component's own
  # comments, and TablerUi::Docs::DemoRegistry's registered ERB demos -- so
  # this file cannot drift the way README.md's hand-written prose did.
  #
  # Pure formatting logic over already-loaded data -- mirrors CssBundle's
  # separation: this module has zero Rails dependency of its own; only the
  # caller (the Rake task) needs a booted Rails app so
  # TablerUi::Docs::Navigation/DocParser/DemoRegistry are available.
  module UsageDoc
    PATH = File.expand_path("../../USAGE.md", __dir__)

    HEADER = <<~MD
      # tabler_ui usage

      > **Generated file.** Do not hand-edit -- run `rake tabler_ui:usage_doc`
      > after changing a component's doc comments or a file under
      > `docs/lib/tabler_ui/docs/demos/`. Source of truth: each component's
      > own doc comments (parsed by `TablerUi::Docs::DocParser`) and its
      > registered demos (`TablerUi::Docs::DemoRegistry`).
    MD

    INSTALL_SECTION = <<~MD
      ## 1. Install

      ```ruby
      gem "tabler_ui", git: "https://github.com/webbastelbude/tabler_ui.git"
      ```

      Pulls in `rails` (>= 7.0), `stimulus-rails`, `ostruct` and
      `sprockets-rails` (~> 3.5) -- the last one is required even on a
      Propshaft host; the next section explains why.

      ## 2. Asset setup

      `app/assets/stylesheets/tabler_ui.css` is a **Sprockets directive
      manifest** -- six `*= require` lines, no CSS of its own. Propshaft has
      no directive processor, so a Propshaft host is served that file's
      comments byte-for-byte: no error, no styling, nothing to point at in
      the console. Pick whichever matches the host app.

      **Sprockets** -- add to `app/assets/stylesheets/application.css`:

      ```
      /*
       *= require tabler_ui
       */
      ```

      **Propshaft (Rails 8 default)** -- link the pre-built, directive-free
      bundle instead:

      ```erb
      <%= stylesheet_link_tag "tabler_ui_all" %>
      ```

      ## 3. JavaScript

      The gem's own `config/importmap.rb` is auto-loaded by the engine, so
      `tabler_ui` and its Stimulus controllers are already pinned. What
      still matters is order: `tabler_ui.js` registers its controllers
      inside `if (window.Stimulus)`, so the host must start Stimulus and
      assign `window.Stimulus` **before** importing `"tabler_ui"`.

      ```js
      // app/javascript/controllers/application.js
      import { Application } from "@hotwired/stimulus"
      const application = Application.start()
      window.Stimulus = application
      export { application }
      ```

      ```js
      // app/javascript/application.js
      import "controllers/application"
      import "tabler_ui"
      ```

      ## 4. Mount the docs engine

      Optional: mount `TablerUi::Docs::Engine` anywhere and every component
      gets a generated reference page plus its live demos.

      ```ruby
      mount TablerUi::Docs::Engine, at: "/ui"
      ```
    MD

    HTML_ATTRIBUTES_SECTION = <<~MD
      ## HTML attributes

      Most components take a hash of HTML attributes for one or more of the
      elements they render. You supply the hash, the component merges it
      onto its own defaults, and the result becomes that element's
      attributes. Every component section below names its own `html:`
      keys; this section is the one place the merge itself is explained.

      ### The naming convention

      `html:` targets a component's root element. A part-specific hook is
      named `<part>_html:`. Card renders three named parts, each with its
      own hook:

      ```ruby
      tabler_ui.card title: "Invoices",
                    header_html: { class: "bg-dark" },
                    body_html:   { class: "p-0" },
                    footer_html: { class: "text-end" } do |slots|
        ...
      end
      ```

      ### The merge rule

      What happens depends on the attribute name, decided by
      `TablerUi::HtmlOptions.merge_html`:

      | Attribute | Rule |
      | --- | --- |
      | `class` | Appended to the component's own classes, deduplicated. Never replaces them. |
      | `data` | Merged one level deep -- your keys and the component's own keys both survive; a key given by both sides, yours wins. |
      | `aria` | Same rule as `data` -- merged one level deep. |
      | anything else | Yours overwrites the component's outright. |

      A worked example -- Button's `confirm:` option already puts a
      `turbo_confirm` key into the root element's `:data`. Adding your own
      `data:` via `html:` does not replace it:

      ```ruby
      tabler_ui.button text: "Delete", color: "danger", confirm: "Are you sure?",
                       html: { data: { testid: "delete-button" } }

      # component's own defaults for the root element:
      { class: "btn btn-danger", data: { turbo_confirm: "Are you sure?" } }

      # your html: option:
      { data: { testid: "delete-button" } }

      # merged -- both data keys survive, class is untouched by data at all:
      { class: "btn btn-danger", data: { turbo_confirm: "Are you sure?", testid: "delete-button" } }
      ```

      ### Per-item hooks: callables

      Parts that repeat -- table rows, pagination links, breadcrumb items --
      also accept a **proc** instead of a Hash. It is called once per item
      and receives that item; whatever Hash it returns is merged exactly
      like a static one. A proc returning `{}` or `nil` contributes
      nothing. Table's `row_html:`:

      ```ruby
      tabler_ui.table columns: columns, data: invoices,
                     row_html: ->(row) { row.overdue? ? { class: "table-danger" } : {} }
      ```

      On the component side, that hook is resolved with
      `html_for(:row, {}, row)` -- the extra argument after the defaults
      hash is what the stored proc gets called with.

      ### When the element doesn't render

      A hook only applies to an element the component actually renders.
      Breadcrumb's `link_html:` targets each item's `<a>` -- but the
      current item, and any item with no `url:`, renders as plain text with
      no `<a>` to apply it to. `link_html:` is silently skipped for that
      item; use the item's own `html:` (part `:item`, its `<li>`) to reach
      it instead.
    MD

    module_function

    def generate
      parts = [HEADER, install_section, html_attributes_section, components_section, form_builder_section]
      "#{parts.join("\n")}\n"
    end

    def install_section
      INSTALL_SECTION
    end

    def html_attributes_section
      HTML_ATTRIBUTES_SECTION
    end

    def components_section
      sections = TablerUi::Docs::Navigation.category_names.map { |category| category_section(category) }
      "## Components\n\n#{sections.join("\n")}"
    end

    def category_section(category)
      names = TablerUi::Docs::Navigation.components_in(category)
      "### #{category}\n\n#{names.map { |name| component_section(name) }.join("\n")}"
    end

    def component_section(name)
      title = TablerUi::Docs::Navigation.title_for(name)
      parsed = TablerUi::Docs::DocParser.find(name)
      demos = TablerUi::Docs::DemoRegistry.for(name.to_sym)

      body = ["#### #{title} -- tabler_ui.#{name}\n"]
      if parsed&.documented?
        body << "#{parsed.description}\n" if parsed.description.present?
        parsed.sections.each { |section| body << doc_section(section) }
        body << options_table(parsed.options) if parsed.options.any?
        body << examples_block(parsed.examples) if parsed.examples.any?
      end
      body << demos_block(demos) if demos.any?
      body << "_No documentation parsed yet._\n" if !parsed&.documented? && demos.empty?
      body.join("\n")
    end

    def doc_section(section)
      heading = "#{'#' * (section.level + 3)} #{section.title}"
      "#{heading}\n\n#{section.body}\n"
    end

    def options_table(options)
      rows = options.map { |option| "| `#{option.name}` | #{option.type} | #{option.description} |" }
      <<~MD
        **Options**

        | Name | Type | Description |
        | --- | --- | --- |
        #{rows.join("\n")}
      MD
    end

    def examples_block(examples)
      blocks = examples.map do |example|
        lead = example.title.present? ? "**#{example.title}**\n\n" : ""
        "#{lead}```ruby\n#{example.code}\n```\n"
      end
      "**Examples**\n\n#{blocks.join("\n")}"
    end

    def demos_block(demos)
      blocks = demos.map { |demo| "**#{demo.title}**\n\n```erb\n#{demo.source.strip}\n```\n" }
      "**Demos**\n\n#{blocks.join("\n")}"
    end

    def form_builder_section
      demos = TablerUi::Docs::DemoRegistry.for(:form_builder)
      blocks = demos.map { |demo| "**#{demo.title}**\n\n```erb\n#{demo.source.strip}\n```\n" }

      intro = <<~MD
        ## Form builder

        `TablerUi::FormBuilder` (`lib/tabler_ui/form_builder.rb`) is an
        `ActionView::Helpers::FormBuilder` subclass, Simple-Form style.
        Reach it via `tabler_form_with` or `tabler_ui_form_for`
        (`lib/tabler_ui/helper.rb`), which each set
        `options[:builder] ||= TablerUi::FormBuilder` and delegate to
        `form_with`/`form_for`.

        ```ruby
        <%= tabler_form_with model: @user do |f| %>
          <%= f.input :name %>
          <%= f.input :email %>
          <%= f.submit "Save" %>
        <% end %>
        ```

        `#input` derives a method name from the DB column type
        (`object_type_for_method`) and dispatches to it via `send` --
        `:string`, `:text`, `:integer`, `:date`, `:boolean`, `:file` and
        `:select` are covered; `:decimal`, `:float`, `:datetime` and
        `:time` route through `string_input`/`string_field`'s own
        finer-grained dispatch. An unrecognised type (and no explicit
        `as:`) raises `ArgumentError` with a message naming the field and
        the resolved input method, rather than a bare `NoMethodError`.
        Pass `as:` to render it explicitly.

        `#error_notification` renders a Tabler alert (via
        `tabler_ui.alert`) from `@object.errors.full_messages` when the
        object has any errors. Per-field errors render inline: a
        `.invalid-feedback` div plus an `is-invalid` class on the field
        itself, driven by `has_error?`.

      MD

      "#{intro}#{blocks.join("\n")}"
    end
  end
end
