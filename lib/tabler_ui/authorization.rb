# frozen_string_literal: true

module TablerUi
  # Shared choke point for the `auth:` gating check (CLAUDE.md rule 8).
  #
  # `!!TablerUi.auth_method.call(value)` is one line, but it has more than one
  # call site: `Ui#method_missing` calls it here for every top-level
  # `tabler_ui.<name>` call, and a later wave adds `auth:` to each of the 11
  # builder-style components' subitem methods (navbar items, dropdown items,
  # tabs, ...), which will call this same helper for their own subitems
  # rather than re-inlining (and re-`!!`-coercing) the check a dozen times.
  module Authorization
    module_function

    # @param value the `auth:` option's value (nil if it was omitted)
    # @return [Boolean] whether the globally configured auth_method
    #   authorizes +value+
    def authorized?(value)
      !!TablerUi.auth_method.call(value)
    end
  end
end
