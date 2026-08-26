# frozen_string_literal: true

module TablerUi
  module Docs
    module Editor
      # The design editor's data contract: the shape of a workspace, the shape
      # of one design tree, and the limits every one of them is held to.
      #
      # Four modules build against this and must agree exactly -- Workspace
      # (validates the multi-file document), Tree (validates one design),
      # Renderer (tree -> HTML) and ErbGenerator (tree -> .html.erb). The
      # constants live here, alone, so none of the four owns them and none can
      # quietly redefine them.
      #
      # ## Why the limits are a security control, not tuning
      #
      # Both endpoints that read this data ship inside a mountable engine, so
      # they run in third-party host apps. A design tree nests, and partial
      # references let one file reach another, so an unbounded document is a
      # trivial stack-overflow DoS. MAX_DEPTH is enforced *before* rendering,
      # not only during it: SystemStackError is not a StandardError, so it
      # escapes the Renderer's per-node rescue and takes the worker down
      # instead of producing an error marker. The pre-check is the real
      # control; the rescue only handles component-level ArgumentError.
      #
      # ## Workspace
      #
      #   { "version"     => 1,
      #     "files"       => { "users/index.html.erb" => { "tree" => <node> } },
      #     "directories" => ["users", "shared"],   # explicit, so empty dirs persist
      #     "open"        => "users/index.html.erb" }
      #
      # A flat path => file map, hierarchy derived by splitting on "/" -- the
      # Git approach. Far simpler to mutate, move and diff than a nested
      # structure, and the explorer renders the tree from it.
      #
      # ## Node kinds
      #
      #   fragment      root only. { "kind", "id", "children" => [] }
      #   row           { "kind", "id", "attrs" => {}, "children" => [] }
      #   column        { "kind", "id", "span" => { "base" => 12, "md" => 6 }, "attrs", "children" }
      #   heading       { "kind", "id", "level" => 1..6, "content" => String }
      #   text          { "kind", "id", "tag" => "p", "content" => String }
      #   component     { "kind", "id", "name" => "modal",
      #                   "args"    => { "id" => "confirm" },  # required positionals, by param name
      #                   "options" => { "title" => "Confirm" },
      #                   "html"    => { "root" => {...}, "header" => {...} },  # keyed by PART
      #                   "slots"   => { "body" => [<node>] },                  # slot-style only
      #                   "items"   => [<builder_item>] }                       # builder-style only
      #
      # `modal` is used above because it is one of the only 8 components that
      # take a required positional at all (the others being accordion,
      # carousel, offcanvas, settings_page, tabs -- all `id` -- plus icon and
      # illustration). Most components, card included, are options-hash only
      # and carry no `args` key.
      #   builder_item  { "kind", "id", "method" => "add",
      #                   "args", "options", "html",
      #                   "children" => [<node>],        # for block: :children methods
      #                   "items"    => [<builder_item>] } # for block: :items methods
      #   partial       { "kind", "id", "path" => "shared/_header.html.erb" }
      #
      # `args` is kept separate from `options` even though the dispatcher
      # extracts required positionals out of one kwargs hash by parameter name
      # -- a separate key lets the validator enforce presence and lets the ERB
      # generator emit the positional first. A key present in both is an error,
      # never a silent merge.
      #
      # `html` is keyed by PART ("root", "header"), not by option key
      # ("html", "header_html"). That is the component's own vocabulary --
      # TablerUi::Base#initialize_html_options does exactly this mapping in
      # reverse -- and it makes the property panel's HTML section mechanical.
      #
      # `slots` and `items` are mutually exclusive: a component is slot-style
      # or builder-style, never both. Component.builder_style? decides.
      #
      # ## Two rules the first draft of this file left open
      #
      # **Over budget drops, it does not fail the tree.** Tripping any of the
      # LIMITS below removes the offending node (or truncates the offending
      # value) and records an error; it never makes the whole document
      # unusable. A design tool must not answer "you have 501 nodes" by
      # refusing to show any of them. Only a structurally unusable root -- not
      # a Hash at all, or its own kind/id invalid -- is fatal. Downstream
      # modules must therefore expect a tree that came back usable *and*
      # carries errors, and a tree smaller than the one that was submitted.
      #
      # **"root" as an html part means different things at the two levels.**
      # On a `component`, `html:` -> part :root is a structural guarantee of
      # TablerUi::Base#initialize_html_options and holds whether or not the
      # doc comment happens to mention :html -- so "root" is always a legal
      # part there. On a `builder_item` there is no such guarantee: per-item
      # HTML hooks are hand-rolled method by method, so "root" is legal only
      # when that specific builder method documents a bare :html option. (A
      # known live example of the asymmetry: navbar's nested
      # DropDownProxy#item exposes only :link_html and has no root part at
      # all, unlike its NavigationGroup sibling.)
      #
      # ## What is deliberately absent
      #
      # There is no raw-HTML node kind, and `content` is always plain text,
      # always escaped, never `raw`/`html_safe`. There is no `auth` anywhere:
      # it is stripped at every level and reported. That is requirement 4 (this
      # is a design tool, not a wiring tool) AND a security control -- `auth:`
      # values are handed to the host's globally configured auth_method block,
      # i.e. arbitrary host code, so letting a POST body choose that value is a
      # channel into host authorization with an attacker-chosen argument.
      #
      # There is no `contenteditable` either. In-canvas text editing is applied
      # at runtime by the editor's own JavaScript, inside the preview frame
      # only, and removed on blur -- neither the Renderer nor the ErbGenerator
      # may ever emit that attribute.
      module Contract
        VERSION = 1

        KINDS = %w[fragment row column heading text component builder_item partial].freeze

        # Node kinds that carry a `children` array of arbitrary child nodes.
        CONTAINER_KINDS = %w[fragment row column].freeze

        # Static-content kinds -- plain text only, no children.
        TEXT_KINDS = %w[heading text].freeze

        TEXT_TAGS = %w[p span div small strong em].freeze
        HEADING_LEVELS = (1..6).freeze

        # "base" plus Bootstrap's own breakpoint names. base: 12, md: 6
        # renders class="col-12 col-md-6".
        SPAN_KEYS = (["base"] + TablerUi::Breakpoint::ALL).freeze
        SPAN_VALUES = ((1..12).to_a + ["auto"]).freeze

        LIMITS = {
          bytes: 262_144,
          files: 200,
          nodes: 500,
          depth: 12,
          string: 5_000,
          options_per_node: 40,
          children_per_node: 100,
          attr_string: 512
        }.freeze

        # A client-generated opaque handle, used only for selection and drag
        # targeting. Never emitted as an HTML id attribute -- the renderer
        # stamps it as data-editor-node-id instead, so it cannot collide with
        # a design's own ids.
        NODE_ID = /\A[a-z0-9_]{1,32}\z/
        # Shape check applied before the Navigation.components allowlist. Both
        # run: the allowlist is the real control (Ui#respond_to_missing? returns
        # true for everything and an unknown name falls through to
        # render "tabler_ui/#{name}" -- partial-path injection), this just
        # rejects obvious junk earlier and more legibly.
        COMPONENT_NAME = /\A[a-z][a-z0-9_]*\z/

        # Rails-aware view paths. A basename starting "_" is a partial;
        # "layouts/" is flagged in the UI but not otherwise special here.
        PATH_SEGMENT = /\A[a-z0-9_]+\z/i
        PATH_SUFFIX = ".html.erb"
        MAX_PATH_SEGMENTS = 8

        # Attribute KEYS need an allowlist, not just escaping: Rails' tag
        # helper escapes attribute values but will happily emit an onclick
        # attribute it is handed.
        ATTR_KEYS = %w[class id title role].freeze
        ATTR_NESTED_KEYS = %w[data aria].freeze
        ATTR_PREFIXES = %w[data- aria-].freeze
        ATTR_DENY = %w[href src srcdoc style formaction action xlink:href].freeze
        ATTR_DENY_PATTERN = /\Aon/i
        # Rejected in any string value anywhere in the document.
        DANGEROUS_VALUE = /\A\s*(javascript|data|vbscript):/i

        # Stripped wherever it appears, at every nesting level. See the
        # "deliberately absent" note above -- this is a security control.
        FORBIDDEN_OPTIONS = %w[auth].freeze
      end
    end
  end
end
