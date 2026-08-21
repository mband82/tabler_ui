# frozen_string_literal: true

require "tabler_ui/docs/engine"
require "tabler_ui/docs/demo"
require "tabler_ui/docs/demo_registry"

# Demo files register their content as soon as the gem loads, not lazily on
# first controller access -- see docs/DEMOS.md ("Where demo files get
# loaded") for why eager beats lazy here (mainly: a demo with a typo'd
# duplicate id fails the whole boot, not just the one page nobody visited
# yet). Demo::DuplicateDemoError from Builder#demo would already have
# surfaced by the time this file finishes requiring.
TablerUi::Docs::DemoRegistry.load_demos!
