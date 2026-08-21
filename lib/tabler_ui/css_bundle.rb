# frozen_string_literal: true

module TablerUi
  # Generates app/assets/stylesheets/tabler_ui_all.css: the concatenated,
  # directive-free stylesheet a Propshaft host links directly with
  # stylesheet_link_tag "tabler_ui_all".
  #
  # app/assets/stylesheets/tabler_ui.css is a Sprockets directive manifest
  # (six `*= require` lines, no CSS of its own). Propshaft has no directive
  # processor, so a Propshaft host is served that comment block byte-for-byte
  # -- no error, just a completely unstyled app. This module resolves the
  # same six `*= require` lines, in the same order (CSS cascade order
  # matters), to real files under app/assets/stylesheets/, and concatenates
  # them verbatim: no reordering, no dedup, no minification.
  #
  # SOURCES is hand-kept in step with the `*= require` lines in tabler_ui.css
  # -- nothing derives one from the other automatically. That is what
  # spec/lib/tabler_ui/css_bundle_spec.rb guards: it (a) regenerates in
  # memory and diffs against the committed tabler_ui_all.css byte for byte,
  # so any of the 6 source files changing without a `rake tabler_ui:css_bundle`
  # run goes red, and (b) parses tabler_ui.css's own `*= require` lines and
  # compares them against SOURCES, so adding/removing/reordering a require
  # line without updating SOURCES to match also goes red.
  module CssBundle
    STYLESHEETS_DIR = File.expand_path("../../app/assets/stylesheets", __dir__)

    # Mirrors, in order, the six `*= require` lines in
    # app/assets/stylesheets/tabler_ui.css.
    SOURCES = %w[
      tabler_ui/tabler.css
      tabler_ui/navbar.css
      tabler_ui/datepicker.css
      tabler_ui/turbo.css
      star-rating.css
      tabler_ui/rating.css
    ].freeze

    HEADER = <<~CSS
      /*
       * tabler_ui_all.css -- GENERATED FILE, do not hand-edit.
       *
       * Concatenation of the files app/assets/stylesheets/tabler_ui.css
       * requires via Sprockets `*= require` directives, in the same order.
       * Propshaft has no directive processor and would otherwise serve that
       * manifest's comments with no CSS in them; link this file instead on
       * a Propshaft host: stylesheet_link_tag "tabler_ui_all".
       *
       * Regenerate with `rake tabler_ui:css_bundle` after editing any of:
       * #{SOURCES.join(", ")}
       */
    CSS

    module_function

    # Absolute paths to the six source files, in cascade order.
    def source_paths
      SOURCES.map { |relative| File.join(STYLESHEETS_DIR, relative) }
    end

    # The generated bundle contents: header comment + each source file's
    # contents, concatenated in order.
    def generate
      body = source_paths.map { |path| File.read(path) }.join("\n")
      "#{HEADER}\n#{body}"
    end
  end
end
