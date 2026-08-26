# frozen_string_literal: true

module TablerUi
  module Docs
    # Namespace for the in-browser design editor's metadata registries --
    # SlotMap, BuilderMap, EnumMap (see each file's own header comment for
    # what it covers and why it's hand-maintained rather than derived at
    # load time).
    #
    # docs/lib is on $LOAD_PATH (gemspec require_paths) but is NOT
    # Zeitwerk-autoloaded and NOT reloaded in development -- same as every
    # other file under docs/lib/tabler_ui/docs. Requiring this one file
    # pulls in all three registries; editing any of them requires a server
    # restart in the docs app. No per-request mutable state anywhere in
    # this namespace.
    module Editor
    end
  end
end

require_relative "editor/slot_map"
require_relative "editor/builder_map"
require_relative "editor/enum_map"
