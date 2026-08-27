# frozen_string_literal: true

require "cgi"
require "tabler_ui/docs/editor/contract"
require "tabler_ui/docs/editor/builder_map"
require "tabler_ui/docs/editor/enum_map"
require "tabler_ui/docs/editor/sort_url"

module TablerUi
  module Docs
    module Editor
      # Turns a validated, normalized design tree (see contract.rb's "Node
      # kinds" section) into the literal .html.erb text a developer pastes
      # into their own app.
      #
      #   TablerUi::Docs::Editor::ErbGenerator.new(node).call # => String
      #
      # Pure formatting over data the Tree validator has already checked --
      # this class does not re-validate, does not re-check contract.rb's
      # LIMITS, and does not defend against a malformed node the way the
      # validator does. Feed it anything but an already-validated tree and
      # its behaviour is undefined. Mirrors lib/tabler_ui/usage_doc.rb's own
      # shape (a pure String builder, a `generate`/`call` entry point, a
      # "generated file" banner in its own output) and, like that file, has
      # zero Rails dependency of its own -- only the stdlib "cgi" library,
      # for HTML-escaping text content and attribute values. It does read
      # TablerUi::Breakpoint (autoloaded by the main engine, see
      # breakpoint.rb) and this directory's own BuilderMap/EnumMap
      # registries (NOT autoloaded -- explicitly required above, same as
      # lib/tabler_ui/usage_doc.rb explicitly requires Navigation/DocParser).
      #
      # ## Call syntax
      #
      # Every emitted call is keyword-args-only, no parens -- e.g.
      # `tabler_ui.modal "confirm-modal", title: "Confirm"`, matching the
      # style contract.rb's own "args" doc uses and the majority of
      # docs/lib/tabler_ui/docs/demos/*.rb. Only the outermost
      # `tabler_ui.<name>` call for a component node is emitted as `<%= %>`
      # -- it is the one call that returns real HTML. Everything nested
      # inside its block (a `slots.<name>` call, any builder sub-item
      # method) is emitted as `<% %>`: both TablerUi::SlotContext#method_missing
      # and every builder method return "" by design (see lib/tabler_ui/ui.rb
      # and, e.g., Tabs::Component#tab's own doc comment), so `<%= %>` there
      # would print a stray empty string on every line.
      #
      # ## Slot blocks are always `do ... end`, never `{ ... }`
      #
      # A `slots` value in the tree is an Array of child nodes (contract.rb:
      # `"slots" => { "body" => [<node>] }`), not a bare string, so a slot's
      # content can never collapse to the brace-block-returning-a-String
      # shorthand a few hand-written demos use (`slots.body { "text" }`).
      # This class always emits the block form instead
      # (`slots.body do ... end`), even for a slot holding exactly one plain
      # text node -- one code path, and every child node still goes through
      # real HTML-escaping on its way out instead of being embedded as a raw
      # Ruby string literal.
      #
      # ## Two hard constraints
      #
      # 1. `contenteditable` is never emitted -- that attribute is applied by
      #    the editor's own in-canvas JavaScript, at runtime, in the preview
      #    frame only (see contract.rb's "What is deliberately absent"
      #    section). Nothing in this class ever writes that string; see
      #    erb_generator_spec.rb's dedicated assertion.
      # 2. This file's own banner comment must never contain the two-character
      #    ERB close sequence inside the comment text -- see
      #    spec/lib/tabler_ui/docs/no_leaked_erb_comment_spec.rb for the two
      #    real bugs that shape guards against.
      #
      # ## What is NOT emitted
      #
      # The client-generated `id` every node carries (contract.rb's NODE_ID)
      # is an opaque editor handle for selection/drag targeting, not part of
      # the developer's own markup -- like `contenteditable`, it is a
      # preview-only concern (the Renderer stamps it as
      # `data-editor-node-id`) and this class never emits it either.
      #
      # ## `table`'s :columns is declarative, not callable
      #
      # `table`'s real :columns option needs a `value:` Proc per column --
      # JSON cannot express one, so a design tree carries a declarative
      # `key:` per column instead, and #format_columns_array emits the real
      # `value: ->(row) { row[:key] }` as literal Ruby source, built from
      # that same `key:`. Renderer#synthesize_table_columns derives the
      # equivalent real Proc from the identical `key:` on the preview side --
      # see that method's doc for why the two independently agreeing is the
      # whole point (consistency_spec.rb is the guard). The `key:` string
      # itself is never emitted as, or treated as, executable code -- only
      # ever read as a plain identifier to build a Symbol/String literal.
      #
      # ## `table`'s :sort_url is declarative too
      #
      # Same problem, same fix: `table`'s real :sort_url option needs a
      # callable (`sort_url.call(key, dir)`), so a design tree carries a
      # declarative Hash instead (see SortUrl's own doc for both modes) and
      # #format_sort_url_value emits the real lambda as literal Ruby
      # source, built via the exact same SortUrl.pattern_for conversion
      # Renderer#synthesize_sort_url uses to build the real Proc -- see
      # that method's doc for why routing both sides through one shared
      # conversion, rather than each re-deriving simple mode's pattern
      # independently, is what keeps them from drifting apart.
      class ErbGenerator
        INDENT = "  "
        WRAP_WIDTH = 100
        BANNER = "<%# Generated by the tabler_ui design editor -- do not hand-edit. %>\n\n"

        # BuilderMap level Symbol => the local variable name a nested
        # builder block is yielded under. Only navbar has levels past :root
        # today (see BuilderMap's "navbar's levels" doc) -- :group is the
        # NavigationGroup yielded by left/right, :dropdown is the
        # DropDownProxy yielded by a group's own #dropdown.
        NESTED_LEVEL_VAR_NAMES = { group: "nav", dropdown: "menu" }.freeze

        # A bareword-safe Ruby identifier -- usable as either a `key:` hash
        # label or a `:key` symbol literal without quoting.
        RUBY_LABEL = /\A[A-Za-z_][A-Za-z0-9_]*[?!]?\z/

        # Hard constraint (see this class's own doc comment): in-canvas
        # editing applies `contenteditable` at runtime, in the preview frame
        # only. The tree contract never allows it through attrs/html in the
        # first place (contract.rb's ATTR_KEYS/ATTR_NESTED_KEYS have no such
        # entry), so the validator is the real control -- this is a second,
        # defense-in-depth check at the one place this class turns a Hash
        # key into a literal HTML attribute or Ruby hash key, in case that
        # first control is ever wrong.
        FORBIDDEN_ATTR = "contenteditable"

        def initialize(node)
          @node = node
        end

        # @return [String] the generated .html.erb source, banner included.
        def call
          "#{BANNER}#{render_node(@node, 0, [])}\n"
        end

        private

        # --- Dispatch ------------------------------------------------------

        def render_node(node, indent, scope)
          case node["kind"]
          when "fragment" then render_children(node["children"], indent, scope)
          when "row" then render_row(node, indent, scope)
          when "column" then render_column(node, indent, scope)
          when "heading" then render_heading(node, indent)
          when "text" then render_text(node, indent)
          when "component" then render_component(node, indent, scope)
          when "partial" then render_partial(node, indent)
          else
            raise ArgumentError, "ErbGenerator: unknown node kind #{node['kind'].inspect}"
          end
        end

        def render_children(children, indent, scope)
          (children || []).map { |child| render_node(child, indent, scope) }.join("\n")
        end

        # --- Layout / text kinds --------------------------------------------

        def render_row(node, indent, scope)
          render_element(node, indent, scope, tag: "div", base_class: "row")
        end

        def render_column(node, indent, scope)
          render_element(node, indent, scope, tag: "div", base_class: column_classes(node["span"] || {}))
        end

        # "base" plus Bootstrap's own breakpoint names, in that fixed order,
        # regardless of what order the tree's own span Hash happens to carry
        # -- {"md" => 6, "base" => 12} and {"base" => 12, "md" => 6} both
        # produce "col-12 col-md-6", never "col-md-6 col-12".
        def column_classes(span)
          (["base"] + TablerUi::Breakpoint::ALL).each_with_object([]) do |breakpoint, classes|
            next unless span.key?(breakpoint)

            value = span[breakpoint]
            classes << (breakpoint == "base" ? "col-#{value}" : "col-#{breakpoint}-#{value}")
          end.join(" ")
        end

        def render_element(node, indent, scope, tag:, base_class:)
          open = "#{pad(indent)}<#{tag}#{build_attr_string(node["attrs"] || {}, base_class)}>"
          body = render_children(node["children"], indent + 1, scope)
          body.empty? ? "#{open}</#{tag}>" : "#{open}\n#{body}\n#{pad(indent)}</#{tag}>"
        end

        def build_attr_string(attrs, base_class)
          pairs = []
          classes = [base_class, attrs["class"]].compact.reject(&:empty?).join(" ")
          pairs << ["class", classes] unless classes.empty?

          attrs.each do |key, value|
            next if key == "class" || key == FORBIDDEN_ATTR

            if %w[data aria].include?(key) && value.is_a?(Hash)
              value.each { |sub_key, sub_value| pairs << ["#{key}-#{sub_key}", sub_value] }
            else
              pairs << [key, value]
            end
          end

          return "" if pairs.empty?

          " #{pairs.map { |key, value| %(#{key}="#{CGI.escapeHTML(value.to_s)}") }.join(' ')}"
        end

        def render_heading(node, indent)
          level = node["level"]
          "#{pad(indent)}<h#{level}>#{CGI.escapeHTML(node['content'].to_s)}</h#{level}>"
        end

        def render_text(node, indent)
          tag = node["tag"]
          "#{pad(indent)}<#{tag}>#{CGI.escapeHTML(node['content'].to_s)}</#{tag}>"
        end

        # --- partial ---------------------------------------------------------

        def render_partial(node, indent)
          "#{pad(indent)}<%= render #{partial_render_path(node['path']).inspect} %>"
        end

        # "shared/_header.html.erb" -> "shared/header": strip the stored
        # PATH_SUFFIX, then the leading underscore off the basename only --
        # a directory segment is never itself prefixed with "_".
        def partial_render_path(path)
          segments = path.delete_suffix(TablerUi::Docs::Editor::Contract::PATH_SUFFIX).split("/")
          segments[-1] = segments[-1].delete_prefix("_")
          segments.join("/")
        end

        # --- component ---------------------------------------------------------

        # An EMPTY "slots"/"items" collection is not a block. Tree normalizes
        # those keys onto every component node, so testing the key's presence
        # rather than its contents emitted `do |slots| %>` immediately
        # followed by `<% end %>` for components carrying neither -- noise in
        # the export, and a silent disagreement with Renderer, which passes no
        # block at all in that case. The two walk the same tree and must agree.
        def render_component(node, indent, scope)
          slots = node["slots"] || {}
          items = node["items"] || []

          if !slots.empty?
            render_slot_component(node, indent, scope)
          elsif !items.empty?
            render_builder_component(node, indent, scope)
          else
            segments = build_segments(node["name"], node["args"], node["options"], node["html"])
            render_call(indent, :output, "tabler_ui.#{node['name']}", segments, block: nil)
          end
        end

        def render_slot_component(node, indent, scope)
          segments = build_segments(node["name"], node["args"], node["options"], node["html"])
          var = unique_name("slots", scope)
          head = render_call(indent, :output, "tabler_ui.#{node['name']}", segments, block: var)
          body = render_slots(node["slots"], indent + 1, scope + [var], var)
          wrap_block(head, body, indent)
        end

        def render_slots(slots, indent, scope, var)
          slots.map do |slot_name, children|
            head = render_call(indent, :bare, "#{var}.#{slot_name}", [], block: :bare)
            wrap_block(head, render_children(children, indent + 1, scope), indent)
          end.join("\n")
        end

        def render_builder_component(node, indent, scope)
          name = node["name"]
          segments = build_segments(name, node["args"], node["options"], node["html"])
          var = unique_name(name, scope)
          head = render_call(indent, :output, "tabler_ui.#{name}", segments, block: var)
          body = render_builder_items(node["items"] || [], indent + 1, scope + [var], name, :root)
          wrap_block(head, body, indent)
        end

        def render_builder_items(items, indent, scope, component_name, level)
          methods = TablerUi::Docs::Editor::BuilderMap.methods_for(component_name, level)
          items.map do |item|
            descriptor = methods[item["method"]] || {}
            render_builder_item(item, indent, scope, component_name, descriptor)
          end.join("\n")
        end

        def render_builder_item(item, indent, scope, component_name, descriptor)
          segments = build_segments(component_name, item["args"], item["options"], item["html"])
          prefix = "#{scope.last}.#{item['method']}"

          case descriptor[:block]
          when :children
            head = render_call(indent, :bare, prefix, segments, block: :bare)
            wrap_block(head, render_children(item["children"] || [], indent + 1, scope), indent)
          when :items
            nested_level = descriptor[:nests]
            var = unique_name(NESTED_LEVEL_VAR_NAMES.fetch(nested_level, nested_level.to_s), scope)
            head = render_call(indent, :bare, prefix, segments, block: var)
            body = render_builder_items(item["items"] || [], indent + 1, scope + [var], component_name, nested_level)
            wrap_block(head, body, indent)
          else
            render_call(indent, :bare, prefix, segments, block: nil)
          end
        end

        # --- shared: args/options/html -> call segments -----------------------

        def build_segments(component_name, args, options, html)
          segments = []
          (args || {}).each_value { |value| segments << format_value(component_name, nil, value) }
          (options || {}).each { |key, value| segments << "#{key}: #{format_value(component_name, key, value)}" }
          ordered_html(html).each { |part, attrs| segments << "#{html_key(part)}: #{format_hash(attrs)}" }
          segments
        end

        # "root" first (it's the component's own :html hook, the primary
        # one), then whatever other parts the node carries, alphabetically
        # -- deterministic regardless of the tree's own Hash order.
        def ordered_html(html)
          return [] if html.nil? || html.empty?

          html.to_a.sort_by { |part, _| part == "root" ? "" : part }
        end

        def html_key(part)
          part == "root" ? "html" : "#{part}_html"
        end

        # A `key: nil` positional arg has no enum concept -- EnumMap is keyed
        # by option *name*, and a positional's name is only ever used here to
        # thread it through this same lookup uniformly; no registered enum
        # entry has a name matching a positional's key, so this is a no-op
        # for args in practice, not a special case.
        def format_value(component_name, key, value)
          if component_name == "table" && key == "columns" && value.is_a?(Array)
            format_columns_array(value)
          elsif component_name == "table" && key == "sort_url" && value.is_a?(Hash)
            format_sort_url_value(value)
          elsif key && TablerUi::Docs::Editor::EnumMap.symbol?(component_name, key)
            format_symbol(value)
          else
            format_scalar(value)
          end
        end

        # --- table :columns -> literal Ruby lambda -----------------------

        # The export-side counterpart to Renderer#synthesize_table_columns
        # -- see that method's doc for the shared story. Where the Renderer
        # builds a real `->(row) { row[key] }` Proc to call immediately,
        # this builds the identical lambda as *source text*, from the same
        # `key`, so a developer pasting the exported ERB into their own app
        # gets working code and the live preview can never show something
        # the export wouldn't actually produce (see consistency_spec.rb).
        # Each column Hash still has String keys here -- ErbGenerator never
        # deep-symbolizes the way Renderer does, it walks the Tree-
        # normalized node directly.
        def format_columns_array(columns)
          return "[]" if columns.empty?

          "[#{columns.map { |col| format_column_entry(col) }.join(', ')}]"
        end

        # A column's editor-only "key" is consumed here, never emitted --
        # Table::Component has no concept of :key, only :label/:class/:sort/
        # :value (see the table component's own @option docs), so the
        # exported code should read like a developer wrote it by hand, not
        # carry a field the real component silently ignores. Any raw
        # "value" the tree happened to carry is dropped the same way, and
        # NEVER formatted as a literal -- only this method's own
        # `key`-derived lambda is ever emitted as the value: (see the
        # class's "Two hard constraints" doc and the module-level note on
        # never turning a user-supplied string into executable code).
        def format_column_entry(col)
          pairs = col.reject { |k, _| %w[key value].include?(k) }.map { |k, v| format_pair(k, v) }
          pairs << "value: #{format_column_value_lambda(col['key'])}"
          "{ #{pairs.join(', ')} }"
        end

        # @param key [String, nil] the column's declarative row key
        # @return [String] literal Ruby source for the synthesized lambda,
        #   e.g. "->(row) { row[:name] }" -- a bareword-safe key emits an
        #   unquoted Symbol literal (`:name`), matching how
        #   Renderer#ruby_label_key would resolve the very same key against
        #   an already-deep-symbolized row Hash; anything else emits a
        #   quoted String key instead, via the same RUBY_LABEL rule.
        def format_column_value_lambda(key)
          if key.nil?
            raise ArgumentError, "table column is missing key: -- ErbGenerator only formats an " \
                                  "already-normalized tree (see this class's own doc comment)"
          end

          "->(row) { row[#{key.match?(RUBY_LABEL) ? ":#{key}" : key.inspect}] }"
        end

        # --- table :sort_url -> literal Ruby lambda -----------------------

        # The export-side counterpart to Renderer#synthesize_sort_url --
        # see that method's doc, and SortUrl's, for the shared story. Where
        # the Renderer builds a real Proc to call immediately, this builds
        # the identical lambda as *source text*. The pattern is only ever
        # interpolated through String#inspect (never raw string
        # interpolation into the generated source) -- a crafted pattern
        # containing, say, a stray `"` or `#{}` must not be able to break
        # out of the string literal it's emitted into and become part of
        # the surrounding Ruby source. The two ".sub" calls are written
        # here as fixed literal Ruby, identical to Renderer's own
        # `.sub("{key}", key.to_s).sub("{dir}", dir.to_s)` -- see this
        # class's "Two hard constraints" doc for the same never-interpolate
        # rule applied to :columns' `key:`.
        #
        # @param hash [Hash] the tree's declarative sort_url value,
        #   String-keyed like every other value ErbGenerator reads (it
        #   never deep-symbolizes -- see the class doc comment)
        # @return [String] literal Ruby source for the synthesized lambda,
        #   e.g. `->(key, dir) { "/users?sort={key}&dir={dir}".sub("{key}",
        #   key.to_s).sub("{dir}", dir.to_s) }`
        def format_sort_url_value(hash)
          pattern = TablerUi::Docs::Editor::SortUrl.pattern_for(hash)
          "->(key, dir) { #{pattern.inspect}.sub(\"{key}\", key.to_s).sub(\"{dir}\", dir.to_s) }"
        end

        def format_symbol(value)
          string = value.to_s
          string.match?(RUBY_LABEL) ? ":#{string}" : ":#{string.inspect}"
        end

        def format_scalar(value)
          case value
          when String then value.inspect
          when Integer then value.to_s
          when true, false then value.to_s
          when nil then "nil"
          when Hash then format_hash(value)
          when Array then "[#{value.map { |element| format_scalar(element) }.join(', ')}]"
          else value.inspect
          end
        end

        # {"class" => "x", "data" => {"controller" => "y"}} ->
        # '{ class: "x", data: { controller: "y" } }'. Nested hash values
        # (an :html hook's own contents, or an option whose value happens to
        # be a Hash) are never enum-checked -- EnumMap only covers a
        # component's own flat option names, never a field nested inside one
        # of their values (contract.rb's "Deliberately excluded" note).
        def format_hash(hash)
          hash = hash.reject { |key, _| key.to_s == FORBIDDEN_ATTR }
          return "{}" if hash.empty?

          "{ #{hash.map { |key, value| format_pair(key, value) }.join(', ')} }"
        end

        def format_pair(key, value)
          key_s = key.to_s
          formatted_value = value.is_a?(Hash) ? format_hash(value) : format_scalar(value)
          key_s.match?(RUBY_LABEL) ? "#{key_s}: #{formatted_value}" : "#{key_s.inspect} => #{formatted_value}"
        end

        # --- call formatting + wrapping -----------------------------------

        # Builds one `<%= ... %>` / `<% ... %>` call, wrapping onto further
        # lines -- aligned under the first segment -- once a line would run
        # past WRAP_WIDTH. `block:` is nil (no block), :bare ("do %>", no
        # yielded var), or a String (the yielded block's local variable
        # name).
        def render_call(indent, macro, prefix, segments, block:)
          tag = macro == :output ? "<%=" : "<%"
          tail =
            case block
            when nil then " %>"
            when :bare then " do %>"
            else " do |#{block}| %>"
            end

          lead = "#{pad(indent)}#{tag} #{prefix}"
          return "#{lead}#{tail}" if segments.empty?

          "#{pack_segments(lead, segments)}#{tail}"
        end

        def pack_segments(lead, segments)
          align = " " * (lead.length + 1)
          lines = []
          current = "#{lead} #{segments.first}"

          segments[1..].each do |segment|
            candidate = "#{current}, #{segment}"
            if candidate.length <= WRAP_WIDTH
              current = candidate
            else
              lines << "#{current},"
              current = "#{align}#{segment}"
            end
          end

          lines << current
          lines.join("\n")
        end

        # --- misc -------------------------------------------------------------

        def wrap_block(head, body, indent)
          body.empty? ? "#{head}\n#{pad(indent)}<% end %>" : "#{head}\n#{body}\n#{pad(indent)}<% end %>"
        end

        # A block-local variable name, suffixed until it doesn't collide
        # with any block variable already open on this same ancestor chain
        # (`scope`, the list of variable names from the root call down to
        # here). Sibling blocks close before the next one opens, so this
        # only ever fires for genuine nesting -- e.g. a partial'd-in
        # fragment that itself renders another slot-style component using
        # the same part name at a deeper level.
        def unique_name(base, scope)
          return base unless scope.include?(base)

          n = 2
          n += 1 while scope.include?("#{base}_#{n}")
          "#{base}_#{n}"
        end

        def pad(indent)
          INDENT * indent
        end
      end
    end
  end
end
