# frozen_string_literal: true

module TablerUi
  module Docs
    module Editor
      # `table`'s :sort_url option is a callable (`sort_url.call(key, dir)`,
      # see Table::Component#sort_url_for / #guard_sort_url!) -- exactly the
      # same "JSON cannot carry a Proc" problem :columns' per-cell :value
      # already has (see Renderer#synthesize_table_columns and
      # ErbGenerator#format_columns_array). A design tree instead carries a
      # declarative Hash under the real option name `sort_url`, in one of
      # two modes:
      #
      #   { "mode" => "simple",  "path" => "/users", "sortParam" => "sort", "dirParam" => "dir" }
      #   { "mode" => "pattern", "pattern" => "/users/sorted/{key}/{dir}" }
      #
      # Tree validates that shape (see tree.rb's
      # #normalize_declarative_sort_url) and drops it -- along with any
      # column's now-dangling `sort:` -- when it's wrong; this module never
      # re-checks any of that, exactly like Renderer/ErbGenerator never
      # re-validate anything else Tree already checked.
      #
      # ## Why simple mode is converted here, and only here
      #
      # Both Renderer#synthesize_sort_url and ErbGenerator#format_sort_url_value
      # need to turn this Hash into the same "{key}"/"{dir}" pattern string
      # before building their own version of the sort_url lambda -- a real
      # Proc, invoked immediately, on the preview side; literal Ruby source,
      # never invoked, on the export side. If each of those two files wrote
      # out its own "#{path}?#{sortParam}={key}&#{dirParam}={dir}", a future
      # change to that formula landing in only one of them would silently
      # break the preview/export agreement consistency_spec.rb exists to
      # catch -- simple mode would quietly fan out into two representations
      # instead of the one this class docs' caller (Renderer/ErbGenerator)
      # is required to build from. Routing both sites through this single
      # function is the fix: the simple-mode formula is written down in
      # exactly one place, ever.
      #
      # ## Symbol- or String-keyed, on purpose
      #
      # Renderer deep-symbolizes every option value before it reaches here
      # (see Renderer#deep_symbolize), so it hands this a Symbol-keyed Hash.
      # ErbGenerator walks the Tree-normalized node directly and never
      # symbolizes anything (see that class's own doc comment on why), so it
      # hands this a String-keyed Hash instead. #fetch reads either shape
      # without making either caller normalize its own Hash first.
      module SortUrl
        module_function

        # @param hash [Hash] the tree's declarative sort_url value, either
        #   Symbol-keyed (Renderer) or String-keyed (ErbGenerator) -- see
        #   this module's own doc comment.
        # @return [String] a pattern containing literal "{key}"/"{dir}"
        #   placeholders, ready for either caller's own
        #   `.sub("{key}", ...).sub("{dir}", ...)` -- pattern mode's own
        #   `pattern` is already in exactly this shape and passes through
        #   unchanged.
        def pattern_for(hash)
          if fetch(hash, :mode) == "simple"
            "#{fetch(hash, :path)}?#{fetch(hash, :sortParam)}={key}&#{fetch(hash, :dirParam)}={dir}"
          else
            fetch(hash, :pattern)
          end
        end

        def fetch(hash, key)
          value = hash[key]
          value.nil? ? hash[key.to_s] : value
        end
      end
    end
  end
end
