# frozen_string_literal: true

require "erb"

module TablerUi
  module Docs
    # Renders a minimal, safe markdown subset for the docs engine: code
    # spans, bullet lists, numbered lists, bold, and paragraph breaks.
    # Nothing else -- no links, no headings (component doc comments already
    # have their own `## `/`### ` heading convention, parsed separately by
    # DocParser into ParsedComponent::Section#title/#level), no HTML
    # passthrough.
    #
    # Called directly by its fully-qualified constant name
    # (`TablerUi::Docs::MarkdownHelper.render(...)`) from the views, exactly
    # the way TablerUi::Docs::Navigation/DocParser/DemoRegistry already are.
    # Lives under docs/app/helpers/ (the conventional Rails::Engine autoload
    # location for anything named "*_helper.rb") rather than docs/lib/,
    # since docs/lib is a separate tree this task does not touch.
    #
    # ## Every method here is a singleton method (`class << self`), on purpose
    #
    # A file named "*_helper.rb" under app/helpers/, defining a module named
    # "*Helper", is exactly the naming convention Rails::Engine's default
    # `include_all_helpers` auto-mixes into *every* view in the app as an
    # ActionView helper module -- regardless of any comment here declaring
    # otherwise. That already happened once: an earlier version of this file
    # defined `render` (and the other methods) via `module_function`, which
    # -- unlike a plain `def self.foo` -- creates a *private instance-method*
    # copy of each method on the module, in addition to the singleton one.
    # Once Rails mixed this module into every view, that private `render`
    # instance method sat directly in the view's own ancestor chain and
    # shadowed ActionView::Helpers::RenderingHelper#render -- breaking every
    # component the real dispatcher (lib/tabler_ui/ui.rb#render_component)
    # renders via `@view.render(...)`, anywhere on any docs page, with
    # "private method 'render' called for an instance of ...". Every
    # component page 500'd.
    #
    # Defining these as singleton methods only (`class << self; def foo;
    # end; end`) adds zero instance methods to this module -- there is
    # nothing for `include` to mix in, so it doesn't matter whether Rails
    # decides to treat this as a helper module or not. See
    # spec/lib/tabler_ui/docs/markdown_helper_spec.rb's "renders on a real
    # docs page, through an actual HTTP request" example, which renders a
    # real component page specifically to catch this class of bug -- a
    # helper-level unit test alone would have kept passing while the site
    # was completely down.
    #
    # ## Why escape first
    #
    # The only inputs today are this gem's own component doc comments
    # (trusted source), but the input is escaped via ERB::Util.html_escape
    # *before* any markdown transform runs, so the result is safe by
    # construction rather than by trust in the source. A literal `<script>`
    # in the input becomes the inert text `&lt;script&gt;` and stays that
    # way -- none of the transforms below touch `<`, `>`, `&`, `"`, or `'`,
    # so an escaped entity just passes through untouched. See
    # markdown_helper_spec.rb's "escapes rather than injects" example.
    module MarkdownHelper
      # Matches a bullet ("* item") or numbered ("1. item") list marker at
      # the start of a line, with optional leading whitespace -- some doc
      # comments nest a list under an extra level of indentation (e.g.
      # avatar's "1. image: ..." intro list). Leading whitespace is not
      # otherwise meaningful here (no nested lists in this minimal subset).
      LIST_MARKER = /\A[ \t]*(?:[*]|\d+\.)[ \t]+/.freeze
      BULLET_MARKER = /\A[ \t]*[*][ \t]+/.freeze

      # Code spans are matched -- and replaced -- before bold, so a literal
      # "**" inside a `code span` is never mistaken for a bold marker.
      CODE_SPAN = /`([^`]+)`/.freeze
      BOLD = /\*\*([^*]+)\*\*/.freeze

      class << self
        # @param text [String, nil] raw doc-comment prose -- may contain
        #   literal blank lines (paragraph breaks) and the markdown subset
        #   documented above. May itself contain arbitrary untrusted-looking
        #   text (see "Why escape first" above).
        # @return [ActiveSupport::SafeBuffer] html_safe HTML -- "" for a
        #   blank/nil input.
        def render(text)
          return "".html_safe if text.blank?

          escaped = ERB::Util.html_escape(text.to_s)

          escaped.split(/\n{2,}/).map { |block| render_block(block) }.join.html_safe
        end

        private

        # A "block" is one paragraph-or-list -- text.split(/\n{2,}/) already
        # cut the input on blank lines, so everything left in +block+ is a
        # single contiguous run of non-blank source lines. Real usage in
        # this corpus (see table's "## Sorting"/"## Filtering") never mixes
        # list lines and plain prose in the same block, so what the *first*
        # line looks like decides the whole block.
        def render_block(block)
          lines = block.split("\n")
          first = lines.first.to_s

          if first.match?(LIST_MARKER)
            render_list(lines, ordered: !first.match?(BULLET_MARKER))
          else
            "<p>#{inline(lines.join(' ').strip)}</p>"
          end
        end

        # Groups +lines+ into list items: a line starting with a marker
        # opens a new `<li>`; any other (non-blank -- blocks never contain
        # blank lines, see #render_block) line is a wrapped continuation of
        # the previous marker line -- e.g. table's "## Sorting" list, where
        # `sort_reset: true` -> nil (...)` continues the item above it on
        # an indented line with no marker of its own.
        def render_list(lines, ordered:)
          items = []

          lines.each do |line|
            if line.match?(LIST_MARKER)
              items << line.sub(LIST_MARKER, "")
            elsif items.any?
              items[-1] = "#{items[-1]} #{line.strip}"
            end
          end

          tag = ordered ? "ol" : "ul"
          "<#{tag}>#{items.map { |item| "<li>#{inline(item.strip)}</li>" }.join}</#{tag}>"
        end

        # Inline transforms only -- code spans, then bold. Order matters:
        # see the CODE_SPAN/BOLD constants' comment above.
        def inline(text)
          text.gsub(CODE_SPAN) { "<code>#{Regexp.last_match(1)}</code>" }
              .gsub(BOLD) { "<strong>#{Regexp.last_match(1)}</strong>" }
        end
      end
    end
  end
end
