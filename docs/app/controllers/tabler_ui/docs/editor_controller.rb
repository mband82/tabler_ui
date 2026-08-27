# frozen_string_literal: true

require "tabler_ui/docs/editor"

module TablerUi
  module Docs
    # Controller for the in-browser design editor: the page shell (#show),
    # its sandboxed preview iframe (#frame), the palette/property-panel
    # payload (#schema) and the live preview render (#preview). See
    # docs/lib/tabler_ui/docs/editor.rb's header comment for the pipeline
    # every action but #show/#frame delegates to.
    #
    # ## CSRF -- on, not skipped
    #
    # `#preview` is the one POST (and the one action that renders
    # attacker-controlled input into HTML server-side) this whole engine
    # has, so it needs real forgery protection -- `skip_forgery_protection`
    # is never an option (see #preview's own comment). Declared explicitly
    # here with `protect_from_forgery with: :exception`, rather than
    # depending on ActionController::Base's own auto-installed default
    # (`config.action_controller.default_protect_from_forgery`, on by
    # default via `config.load_defaults` in a real host app): that
    # auto-install is boot-*order*-sensitive -- it only fires if
    # `action_controller/railtie` has loaded by the time `load_defaults`
    # runs -- and this gem's own Combustion spec harness (spec/rails_helper.rb)
    # requires combustion, which calls `load_defaults`, *before* requiring
    # `action_controller/railtie`, so the default silently never applies
    # there. A real host app's own boot order is very likely fine, but nothing
    # here should stake this endpoint's security on getting boot order right
    # in every possible host -- declaring it directly makes protection
    # unconditional, regardless.
    #
    # The `:exception` strategy raises on a missing/invalid token, and by
    # default that raise renders Rails' own HTML error page -- wrong here
    # (see #preview's "always JSON" reasoning), so it's rescued below into
    # the same JSON error shape every other #preview rejection uses.
    class EditorController < ApplicationController
      protect_from_forgery with: :exception

      rescue_from ActionController::InvalidAuthenticityToken, with: :render_forgery_rejected

      def show
        @nav_current = Navigation::EDITOR
      end

      # Rendered inside <iframe src="<%= editor_frame_path %>"> on the show
      # page, under its own minimal layout (editor_frame, not the shared
      # docs chrome) -- see that layout's header comment for why: the frame
      # shows the design being built, never editor UI.
      def frame
        render layout: "tabler_ui/docs/editor_frame"
      end

      def schema
        render json: Editor::Schema.as_json
      end

      # POST { path:, workspace:, decorate: } -> { html:, erb:, workspace:,
      # errors: [] } on success, { errors: [...] } with a 422 on any kind of
      # rejection.
      #
      # `decorate:` is optional and, absent or anything other than the
      # literal JSON `true`, off -- see Editor::Renderer's own "Decoration"
      # class docs for what it turns on (design-editor canvas "layout
      # guide" markup) and why a stray truthy-but-not-`true` value (a
      # String `"true"`, `1`, ...) must never be treated as opting in: this
      # `== true` check, plus Renderer's own `decorate: false` default, is
      # the entire reachability story for that feature -- there is no other
      # path to `decorate: true` anywhere in this codebase. It only ever
      # affects `html:` below; `erb:` goes through Editor::ErbGenerator,
      # which has no decoration concept at all and never will (see that
      # class's own docs) -- so the export a developer copies out of this
      # endpoint is never contaminated by editor-only guide markup.
      #
      # Response is ALWAYS JSON, on every path -- success, a fatal
      # workspace, a path that doesn't resolve, malformed JSON, an
      # oversized body, a missing/invalid CSRF token. This endpoint turns
      # an attacker-controlled request body into rendered HTML server-side
      # (via Editor::Renderer); if it ever answered with THAT HTML as the
      # response body/content-type, a link (or an auto-submitting form) built
      # around a crafted body would reflect arbitrary markup back on this
      # engine's own origin -- a reflected-HTML/XSS gadget against every
      # host app that mounts it. `render json:` on every branch (never
      # `render inline:`, never falling through to Rails' default HTML
      # error page) is what closes that off.
      def preview
        return reject_oversized_body if body_too_large?

        raw = parse_json_body
        return render_bad_json unless raw

        result = Editor::Workspace.call(raw["workspace"])
        return render_workspace_errors(result) if result.fatal?

        tree = result.workspace.dig("files", raw["path"], "tree")
        return render_missing_path(result, raw["path"]) unless tree

        render json: {
          html: Editor::Renderer.new(html_view_context, resolve: result.resolve,
                                                          decorate: decorate_flag(raw)).render(tree),
          erb: Editor::ErbGenerator.new(tree).call,
          workspace: result.workspace,
          errors: result.errors
        }
      rescue StandardError => e
        # Renderer isolates a bad node into an inline marker, but ErbGenerator
        # deliberately does not: its contract is "already-validated trees
        # only", so it raises rather than inventing output for a shape Tree
        # should have rejected. That asymmetry means a tree Tree let through
        # but the generator refuses would otherwise escape as Rails' HTML
        # exception page -- breaking the always-JSON rule above, which exists
        # precisely so this endpoint can never become a reflected-HTML gadget
        # on a host's origin. Every exit from #preview stays JSON, including
        # this one. A raise here is a Tree gap, so it is reported, not
        # swallowed silently.
        render json: { errors: ["could not generate this design: #{e.message}"] },
               status: :unprocessable_entity
      end

      private

      # #preview responds as JSON, so its lookup context defaults to
      # `formats: [:json]` -- and every component partial in this gem is
      # `_component.html.erb`. Rendering the design through the request's own
      # view context therefore resolves nothing and every component comes back
      # as a "Missing partial" error marker. The marker is still a String in
      # the `html:` field, so a spec asserting only that `html` is present
      # passes while the live editor shows nothing but red boxes -- which is
      # exactly what happened. Pin the formats to :html for the design render.
      def html_view_context
        view_context.tap { |context| context.lookup_context.formats = [:html] }
      end

      # @return [Boolean] see #preview's own doc for why only a literal
      #   JSON `true` counts -- `raw["decorate"]` is `nil` on an absent
      #   key, so this also covers "the client never sent one at all"
      #   without a separate `key?` check.
      def decorate_flag(raw)
        raw["decorate"] == true
      end

      # Rejected before JSON.parse ever runs -- parsing a huge body just to
      # then reject it is the DoS this guards against. `content_length` is
      # a header the client sends, not a measurement of what's actually on
      # the wire, but it's exactly what's being guarded against here: a
      # client that lies about a small body while sending a huge one hits
      # this same cap from the other direction (the connection stalls /
      # errors well before Rails hands a well-formed String to #parse_json_body).
      def body_too_large?
        request.content_length.to_i > Editor::Contract::LIMITS.fetch(:bytes)
      end

      def reject_oversized_body
        limit = Editor::Contract::LIMITS.fetch(:bytes)
        render json: { errors: ["request body exceeds the #{limit}-byte limit"] }, status: :unprocessable_entity
      end

      # @return [Hash, nil] the parsed body, or nil for anything that isn't
      #   well-formed JSON or isn't a top-level object -- Editor::Workspace
      #   and Editor::Tree only ever validate a Hash (Contract's own
      #   "Workspace" shape), so anything else is rejected here rather than
      #   handed down a layer for a less specific error.
      def parse_json_body
        raw = JSON.parse(request.body.read)
        raw.is_a?(Hash) ? raw : nil
      rescue JSON::ParserError
        nil
      end

      def render_bad_json
        render json: { errors: ["request body must be a JSON object"] }, status: :unprocessable_entity
      end

      def render_workspace_errors(result)
        render json: { errors: result.errors }, status: :unprocessable_entity
      end

      def render_missing_path(result, path)
        render json: { errors: result.errors + ["path: #{path.inspect} does not name a file in the workspace"] },
               status: :unprocessable_entity
      end

      def render_forgery_rejected
        render json: { errors: ["invalid or missing CSRF token"] }, status: :unprocessable_entity
      end
    end
  end
end
