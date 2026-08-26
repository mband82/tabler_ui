# frozen_string_literal: true

module TablerUi
  module Docs
    # Namespace for the in-browser design editor.
    #
    # Contract is the workspace and design-tree data contract every other file
    # here is held to. SlotMap, BuilderMap and EnumMap are the metadata
    # registries (see each file's own header for what it covers and why it's
    # hand-maintained rather than derived at load time). Then the pipeline:
    # Tree validates and normalizes one design, Renderer turns a normalized
    # tree into preview HTML through the real dispatcher, and ErbGenerator
    # turns the same tree into exportable .html.erb.
    #
    # Renderer and ErbGenerator both assume Tree has already run and neither
    # re-validates -- Tree is the security boundary, and it is the only one of
    # the three that may be handed untrusted input.
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

require_relative "editor/contract"
require_relative "editor/slot_map"
require_relative "editor/builder_map"
require_relative "editor/enum_map"
require_relative "editor/tree"
require_relative "editor/renderer"
require_relative "editor/erb_generator"
