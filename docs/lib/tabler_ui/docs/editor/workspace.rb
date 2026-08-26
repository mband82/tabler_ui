# frozen_string_literal: true

require_relative "contract"
require_relative "tree"

module TablerUi
  module Docs
    module Editor
      # Validates and normalizes one design-editor **workspace** -- the
      # multi-file document Contract's "Workspace" section describes -- from
      # an untrusted payload. Sits one level above Tree: Tree validates a
      # single design; this validates the file map around it (paths, the
      # `open` pointer, `directories`) and the partial reference graph that
      # spans files.
      #
      # ## Security boundary -- same guarantee as Tree, one file up
      #
      # `raw_workspace` is whatever the editor's save endpoint received --
      # attacker-controlled, arbitrarily shaped. #call NEVER raises: a
      # hostile or malformed payload always comes back as a Result with
      # errors, never an exception. The only things that may raise out of
      # this class are genuine bugs in this file itself, and even those are
      # caught by the last-resort rescue in .call and turned into a fatal
      # Result -- a bug here degrades to "reject the workspace", not "crash
      # the request". Every recursive walk in this file (partial-graph
      # traversal, cycle detection) only ever runs over *already-normalized*
      # output -- either this file's own `files` Hash (capped at
      # `Contract::LIMITS[:files]` entries) or a `tree` that already passed
      # through `Tree.call`, which guarantees bounded depth and no actual
      # Ruby-level object cycles (every node it returns is freshly built, not
      # aliased from the raw input). So none of the walks here need their own
      # depth guard the way Tree's `sanitize_generic_value` does -- the bound
      # was already enforced one layer down.
      #
      # ## A partial's `path` NEVER reaches Rails' `render`
      #
      # Same control Contract's header and Tree's class doc both call out:
      # resolving a `partial` node's `path` to another file's tree happens
      # *only* inside this validated workspace (see `Result#resolve`) and the
      # tree Hash it hands back is walked by Renderer's own dispatcher, the
      # same way any other node is -- the path string itself is never passed
      # to Rails' `render`, ActionView's template lookup, or anything that
      # would let a crafted path escape into the host app's view paths.
      #
      # ## What "normalized" means
      #
      # `Result#workspace` is `{ "version", "files", "directories", "open" }`
      # with `"version"` always equal to `Contract::VERSION` (or the whole
      # thing is fatal -- see rule 1 below), `"files"` a path => `{ "tree" }`
      # Hash of only the files that survived, `"directories"` a deduplicated
      # Array with anything implied by a file path removed, and `"open"`
      # always naming a surviving file (or nil if there are none).
      #
      # ## What happens to an invalid file
      #
      # Same "drop and keep going" philosophy as Tree (see Contract's "Over
      # budget drops" note): an invalid path, a fatal tree, or an
      # over-the-cap entry drops *that file* with an error, never the whole
      # workspace. Only a structurally unusable root -- not a Hash at all, or
      # a `version` that doesn't match -- is fatal (`Result#workspace` nil).
      #
      # ## Cycle handling: paths are *removed from `resolve`*, files are not deleted
      #
      # A `partial` node's `path` can point anywhere in the workspace,
      # including back the way it came -- `a` renders `b` renders `a`. Two
      # options were on the table: (1) mutate the specific `partial` node
      # that closes each cycle so it can never resolve, or (2) exclude every
      # file that participates in *any* cycle from the graph `resolve`
      # exposes, full stop. This picks (2).
      #
      # Reasoning: `Renderer#resolve` is `#call(path) -> tree or nil`, with
      # no notion of *who* is asking -- it can't tell "the reference from `a`
      # to `b`" apart from "the reference from `c` to `b`". So per-edge
      # removal would need this class to reach into and mutate a specific
      # node buried inside another file's already-normalized tree, which
      # both duplicates Tree's node-shape knowledge here and is unnecessary:
      # if resolving `b` can ever lead back to `b`, then `b` is unsafe as a
      # partial-render target *no matter who references it* -- there is no
      # entry point into `b` that doesn't eventually loop. So excluding every
      # file that took part in a cycle from `resolve` (see `Result#resolve`)
      # is not a coarser approximation of the precise fix, it *is* the
      # precise fix, and it is one flat Hash filter instead of a tree walk
      # with mutation. The affected files are **not** removed from
      # `Result#workspace["files"]` -- they are still real, editable files
      # the explorer must keep showing; only their use as a partial-render
      # *target* is neutralized. A reference into a cyclic file renders
      # exactly like a broken reference does -- Renderer's existing
      # `render_partial_node` already turns a `resolve` miss into an inline
      # "unresolved partial" marker, so no change was needed there.
      #
      # Every detected cycle is also reported as one error naming the full
      # path (`"cycle detected: a.html.erb -> b.html.erb -> a.html.erb"`),
      # for the editor UI to surface to the designer.
      #
      # ## Broken partial references
      #
      # A `partial` node whose `path` names no file in the workspace is
      # recorded as an error but is deliberately **not** fatal and does
      # **not** drop the referencing file -- Renderer already renders an
      # unresolved partial as an inline marker (see above), so a dangling
      # reference is a normal, recoverable state while a design is being
      # built (the target file just hasn't been created yet).
      #
      # ## `directories` normalization
      #
      # Duplicates are dropped. A directory already implied by some file's
      # own path (e.g. "users" is implied by "users/index.html.erb") is also
      # dropped -- Contract's own comment says `directories` exists only "so
      # empty dirs persist", so a directory that already has a file in it
      # doesn't need an explicit entry; keeping it anyway would just be a
      # redundant fact for the explorer to reconcile against `files` on every
      # render. This is the optional half of rule 5; documented here per the
      # brief's "your call, document it".
      class Workspace
        # @!attribute workspace
        #   @return [Hash, nil] the normalized workspace, or nil if the
        #     workspace as a whole is unusable (missing/mismatched version,
        #     or not even a Hash)
        # @!attribute errors
        #   @return [Array<String>] every problem found, in the order
        #     encountered
        # @!attribute cyclic_paths
        #   @return [Array<String>] file paths excluded from `#resolve`
        #     because they participate in a partial-reference cycle -- not
        #     part of the primary public contract (`workspace`/`errors`/
        #     `fatal?`/`resolve`), kept as a Result field only because
        #     `#resolve` needs it and recomputing it there would mean
        #     walking every file's tree a second time.
        Result = Struct.new(:workspace, :errors, :cyclic_paths) do
          def fatal?
            workspace.nil?
          end

          # @return [#call, nil] a resolver in exactly the shape
          #   `Renderer.new(view, resolve:)` expects -- `#call(path)` returns
          #   that file's normalized tree Hash, or nil. nil if the workspace
          #   itself is fatal. See the class docs' "Cycle handling" section
          #   for why cyclic paths are excluded here rather than mutated
          #   into the trees themselves.
          def resolve
            return nil if workspace.nil?

            cyclic = cyclic_paths || []
            graph = {}
            workspace["files"].each do |path, entry|
              graph[path] = entry["tree"] unless cyclic.include?(path)
            end
            ->(path) { graph[path] }
          end
        end

        # @param raw_workspace the untrusted payload (see Contract's
        #   "Workspace" section for the intended shape -- anything else is
        #   handled, never raised on)
        # @return [Result]
        def self.call(raw_workspace)
          new.call(raw_workspace)
        end

        def call(raw_workspace)
          @errors = []
          @cyclic_paths = []

          workspace = normalize(raw_workspace)
          Result.new(workspace, @errors, @cyclic_paths)
        rescue StandardError => e
          # Last-resort net -- see the class docs' security section. Every
          # real code path above is written to degrade to an error message
          # instead of raising; this only catches a bug in that code.
          Result.new(nil, (@errors || []) + ["internal error: #{e.class}: #{e.message}"], [])
        end

        private

        # --- Top level -------------------------------------------------------

        def normalize(raw)
          unless raw.is_a?(Hash)
            add_error("workspace: expected an object, got #{raw.class}")
            return nil
          end

          raw = stringify_keys(raw)
          return nil unless valid_version?(raw["version"])

          files = normalize_files(raw["files"])
          directories = normalize_directories(raw["directories"], files.keys)
          open = normalize_open(raw["open"], files)

          workspace = {
            "version" => Contract::VERSION,
            "files" => files,
            "directories" => directories,
            "open" => open
          }

          @cyclic_paths = detect_partial_cycles(files)

          workspace
        end

        # --- version (rule 1) -------------------------------------------------

        # Fatal on any mismatch -- see the class docs' rationale (a higher
        # version is another tab running a newer editor; silently
        # downgrading it would lose work). A lower version is reserved for a
        # future migration step: once Contract::VERSION is ever bumped, a
        # migration table keyed by (raw_version..Contract::VERSION) belongs
        # here, applied before the rest of #normalize runs. For now there is
        # nothing to migrate from, so it is unsupported, same as an
        # unrecognised version.
        def valid_version?(raw_version)
          unless raw_version.is_a?(Integer)
            add_error("workspace.version: must be an Integer, got #{raw_version.inspect}")
            return false
          end

          if raw_version > Contract::VERSION
            add_error("workspace.version: #{raw_version} is newer than this editor supports " \
                       "(#{Contract::VERSION}); refusing to guess-parse a document saved by a newer editor")
            return false
          end

          if raw_version < Contract::VERSION
            add_error("workspace.version: #{raw_version} is older than current (#{Contract::VERSION}); " \
                       "no migration path implemented yet -- migrations land in .valid_version?")
            return false
          end

          true
        end

        # --- files (rules 2, 3, 4) ---------------------------------------------

        def normalize_files(raw_files)
          raw_files = as_capped_hash(raw_files, limit: Contract::LIMITS[:files], label: "files")

          files = {}
          raw_files.each do |path, entry|
            unless valid_file_path?(path)
              add_error("files.#{path.inspect}: invalid path, file dropped")
              next
            end

            unless entry.is_a?(Hash)
              add_error("files.#{path}: expected an object with a 'tree' key, got #{entry.class}, file dropped")
              next
            end

            tree = normalize_file_tree(path, stringify_keys(entry)["tree"])
            files[path] = { "tree" => tree } if tree
          end
          files
        end

        # @return [Hash, nil] the file's normalized tree, or nil (with an
        #   error already recorded) if Tree.call found it fatal.
        def normalize_file_tree(path, raw_tree)
          result = Tree.call(raw_tree)
          result.errors.each { |e| add_error("#{path}: #{e}") }

          if result.fatal?
            add_error("#{path}: tree is fatal, file dropped")
            return nil
          end

          result.node
        end

        # Rails-aware view path rules from Contract: must end with
        # PATH_SUFFIX, no leading "/", every segment (the ".html.erb" already
        # stripped) matches PATH_SEGMENT, at most MAX_PATH_SEGMENTS of them.
        # "..", ".", empty segments and backslashes are all rejected by
        # PATH_SEGMENT itself -- none of those characters are in
        # `[a-z0-9_]` -- same reasoning as Tree#validate_partial_path, which
        # this mirrors exactly (kept as a separate copy rather than a shared
        # helper: Tree's version is a private method on a different class
        # with no public entry point to reuse).
        def valid_file_path?(path)
          return false unless path.is_a?(String)
          return false unless path.end_with?(Contract::PATH_SUFFIX)
          return false if path.start_with?("/")

          segments = path.delete_suffix(Contract::PATH_SUFFIX).split("/", -1)
          return false if segments.length > Contract::MAX_PATH_SEGMENTS

          segments.any? && segments.all? { |s| Contract::PATH_SEGMENT.match?(s) }
        end

        # --- directories (rule 5) ----------------------------------------------

        def normalize_directories(raw_dirs, file_paths)
          unless raw_dirs.nil? || raw_dirs.is_a?(Array)
            add_error("directories: expected an array, got #{raw_dirs.class}, ignoring")
            raw_dirs = []
          end

          implied = implied_directories(file_paths)

          # A Hash-as-ordered-set: dedupes while preserving first-seen order,
          # same trick `Tree#normalize_options`'s callers rely on elsewhere.
          out = {}
          (raw_dirs || []).each do |dir|
            unless valid_directory_path?(dir)
              add_error("directories.#{dir.inspect}: invalid directory path, dropped")
              next
            end
            next if implied.include?(dir)

            out[dir] = true
          end
          out.keys
        end

        # Same segment rules as a file path, minus the ".html.erb" suffix
        # requirement -- a directory has none.
        def valid_directory_path?(path)
          return false unless path.is_a?(String) && !path.empty?
          return false if path.start_with?("/")

          segments = path.split("/", -1)
          return false if segments.length > Contract::MAX_PATH_SEGMENTS

          segments.any? && segments.all? { |s| Contract::PATH_SEGMENT.match?(s) }
        end

        # Every proper ancestor of every file path, e.g. "a/b/c.html.erb"
        # implies both "a" and "a/b".
        def implied_directories(file_paths)
          implied = []
          file_paths.each do |path|
            segments = path.delete_suffix(Contract::PATH_SUFFIX).split("/")
            (0...(segments.length - 1)).each { |i| implied << segments[0..i].join("/") }
          end
          implied.uniq
        end

        # --- open (rule 6) ------------------------------------------------------

        def normalize_open(raw_open, files)
          return raw_open if raw_open.is_a?(String) && files.key?(raw_open)

          fallback = files.keys.sort.first
          add_error("open: #{raw_open.inspect} does not name a file that survived validation, " \
                     "falling back to #{fallback.inspect}")
          fallback
        end

        # --- partial reference graph + cycles (rule 7) --------------------------

        # @return [Array<String>] file paths to exclude from `Result#resolve`
        #   -- see the class docs' "Cycle handling" section.
        def detect_partial_cycles(files)
          graph = build_reference_graph(files)
          report_broken_references(graph, files)
          find_cycles(graph)
        end

        def build_reference_graph(files)
          files.each_with_object({}) do |(path, entry), graph|
            targets = []
            walk_partials(entry["tree"]) { |p| targets << p }
            graph[path] = targets.uniq
          end
        end

        # Every `partial` node in a tree, at any depth -- containers'
        # `children`, a slot-style component's `slots` (Hash of Arrays), and
        # a builder-style component's / builder_item's `items` (Array of
        # builder_item, which may itself carry `children` or nested `items`)
        # are all walked the same way Tree itself produces them (see
        # Contract's "Node kinds"). Safe to recurse unboundedly here -- see
        # the class docs' security section on why `entry["tree"]` is already
        # depth-bounded and cycle-free by construction.
        def walk_partials(node, &block)
          return unless node.is_a?(Hash)

          yield node["path"] if node["kind"] == "partial" && node["path"]

          Array(node["children"]).each { |c| walk_partials(c, &block) }
          (node["slots"] || {}).each_value { |arr| Array(arr).each { |c| walk_partials(c, &block) } }
          Array(node["items"]).each { |c| walk_partials(c, &block) }
        end

        # A `partial` pointing at a path with no file -- reported, never
        # fatal, never drops the referencing file. See the class docs.
        def report_broken_references(graph, files)
          graph.each do |path, targets|
            targets.each do |target|
              next if files.key?(target)

              add_error("#{path}: partial reference to #{target.inspect} does not resolve to any file " \
                         "in the workspace")
            end
          end
        end

        # Classic DFS cycle detection (white/gray/black) over the file-path
        # graph. A back edge to a node still on the stack closes a cycle;
        # the full stack from that node onward, plus the repeated node, is
        # the cycle path reported in the error. Every file path on that
        # stack segment is collected into `cyclic` so `Result#resolve` can
        # exclude all of them -- see the class docs for why exclusion is
        # per-file, not per-edge. Bounded by file count (<= LIMITS[:files]),
        # so no recursion-depth concern.
        def find_cycles(graph)
          color = {}
          cyclic = []

          graph.each_key do |start|
            next if color[start] == :black

            visit_for_cycles(start, graph, color, [], cyclic)
          end
          cyclic.uniq
        end

        def visit_for_cycles(node, graph, color, stack, cyclic)
          color[node] = :gray
          stack.push(node)

          (graph[node] || []).each do |neighbor|
            next unless graph.key?(neighbor) # broken reference, not a cycle -- reported separately

            case color[neighbor]
            when :gray
              idx = stack.index(neighbor)
              cycle = stack[idx..] + [neighbor]
              add_error("cycle detected: #{cycle.join(' -> ')}")
              cyclic.concat(stack[idx..])
            when nil
              visit_for_cycles(neighbor, graph, color, stack, cyclic)
            end
          end

          stack.pop
          color[node] = :black
        end

        # --- Small shared helpers -------------------------------------------------

        def stringify_keys(value)
          value.is_a?(Hash) ? value.each_with_object({}) { |(k, v), h| h[k.to_s] = v } : {}
        end

        def as_capped_hash(value, limit:, label:)
          unless value.nil? || value.is_a?(Hash)
            add_error("#{label}: expected an object, got #{value.class}")
            return {}
          end

          hash = stringify_keys(value)
          return hash unless hash.size > limit

          add_error("#{label}: #{hash.size} entries exceeds the #{limit} limit; extras dropped")
          hash.first(limit).to_h
        end

        def add_error(message)
          @errors << message
        end
      end
    end
  end
end
