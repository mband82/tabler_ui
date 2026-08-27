// localStorage-backed workspace store for the design editor, plus the
// path-manipulation helpers every other editor module needs.
//
// ## Keys
//
// Namespaced "tabler-ui-docs-editor:*" -- the gem already owns an
// unprefixed "theme" key (see app/javascript/controllers/tabler_ui/
// dark_mode_controller.js), so nothing here may collide with that.
//
//   tabler-ui-docs-editor:workspace  the full normalized workspace (every
//                                    file's tree, potentially large)
//   tabler-ui-docs-editor:index      a lightweight { paths, directories,
//                                    open } snapshot, written alongside the
//                                    full workspace on every save -- the
//                                    Explorer only ever needs this, so it
//                                    never has to JSON.parse every file's
//                                    whole design tree just to draw the
//                                    file list.
//   tabler-ui-docs-editor:guides     "true"/"false" -- whether the canvas
//                                    requests decorated (layout-guide)
//                                    previews. Default on (a missing key
//                                    reads as enabled, not disabled -- see
//                                    editor_controller.js's own loader).
//                                    A single boolean has no shape worth a
//                                    load/save pair of its own the way the
//                                    workspace document has above, so
//                                    editor_controller.js reads/writes this
//                                    key directly with plain
//                                    localStorage.getItem/setItem rather
//                                    than through a helper here -- GUIDES_KEY
//                                    is exported below purely so that
//                                    direct read/write still goes through
//                                    one named constant instead of a
//                                    string literal repeated at each call
//                                    site.
//   tabler-ui-docs-editor:inspector-width  the Inspector rail's user-chosen
//                                    width in px, read/written by
//                                    editor_inspector_resize_controller.js
//                                    (not this module -- same one-value,
//                                    no-load/save-pair reasoning as
//                                    GUIDES_KEY just above). A missing or
//                                    unparseable value falls back to that
//                                    controller's own DEFAULT_WIDTH.
//
// ## localStorage is the source of truth
//
// Same discipline as dark_mode_controller.js's own header comment: Turbo
// connects and disconnects Stimulus controllers on every visit that swaps
// the page, so nothing here is safe to trust as in-memory state across a
// reconnect -- the controller re-reads via #loadWorkspace on every
// connect() rather than caching across instances. Every CRUD helper below
// is a pure function -- it returns a NEW workspace object and never
// mutates the one it was given -- so the controller decides once, in one
// place (#saveWorkspace), when a change actually reaches storage.
//
// ## Failure handling
//
// #loadWorkspace never throws -- a missing key, a non-JSON value, or a
// parsed value that isn't a real workspace document all fall back to
// #emptyWorkspace(), with a human-readable `error` the controller can
// surface instead of silently pretending nothing happened.
//
// #saveWorkspace DOES throw -- a write failure (most importantly
// QuotaExceededError) must never be swallowed, or an edit the user thinks
// is saved quietly isn't. The controller is responsible for catching this
// and telling the user.
import * as Tree from "controllers/tabler_ui/docs/editor/tree"

const PREFIX = "tabler-ui-docs-editor:"
export const WORKSPACE_KEY = `${PREFIX}workspace`
export const INDEX_KEY = `${PREFIX}index`
export const GUIDES_KEY = `${PREFIX}guides`
export const INSPECTOR_WIDTH_KEY = `${PREFIX}inspector-width`

const DEFAULT_PATH = "index.html.erb"

// --- Workspace document -----------------------------------------------

export function emptyWorkspace() {
  return {
    version: 1,
    files: {
      [DEFAULT_PATH]: { tree: { kind: "fragment", id: "root", children: [] } }
    },
    directories: [],
    open: DEFAULT_PATH
  }
}

// @return {workspace, error} -- error is null on a clean load or a clean
//   first run (nothing stored yet); a String otherwise, for the caller to
//   surface. Never throws.
export function loadWorkspace() {
  let raw
  try {
    raw = localStorage.getItem(WORKSPACE_KEY)
  } catch (e) {
    return { workspace: emptyWorkspace(), error: `could not read local storage: ${e.message}` }
  }

  if (!raw) return { workspace: emptyWorkspace(), error: null }

  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    return { workspace: emptyWorkspace(), error: `stored workspace was corrupt (${e.message}) -- starting fresh` }
  }

  if (!parsed || typeof parsed !== "object" || typeof parsed.files !== "object") {
    return { workspace: emptyWorkspace(), error: "stored workspace was not a valid document -- starting fresh" }
  }

  return { workspace: parsed, error: null }
}

// Persists both the full document and its lightweight index. Throws on
// failure (see the module doc's "Failure handling" section) -- callers
// must not swallow this.
// @return {Object} the index that was written, so a caller that only needs
//   the index doesn't have to rebuild it separately.
export function saveWorkspace(workspace) {
  const index = buildIndex(workspace)
  try {
    localStorage.setItem(WORKSPACE_KEY, JSON.stringify(workspace))
    localStorage.setItem(INDEX_KEY, JSON.stringify(index))
  } catch (e) {
    throw new Error(`could not save to local storage: ${e.message}`)
  }
  return index
}

export function buildIndex(workspace) {
  return {
    paths: Object.keys(workspace.files || {}).sort(),
    directories: [...(workspace.directories || [])].sort(),
    open: workspace.open || null
  }
}

// --- Path helpers --------------------------------------------------------

export function dirname(path) {
  const idx = path.lastIndexOf("/")
  return idx === -1 ? "" : path.slice(0, idx)
}

export function basename(path) {
  const idx = path.lastIndexOf("/")
  return idx === -1 ? path : path.slice(idx + 1)
}

export function isPartial(path) {
  return basename(path).startsWith("_")
}

export function isLayout(path) {
  return path.startsWith("layouts/")
}

function withSuffix(path) {
  return path.endsWith(".html.erb") ? path : `${path}.html.erb`
}

// Appends "-2", "-3", ... before the .html.erb suffix until `files` has no
// entry at that path. Never overwrites an existing file silently.
function uniquePath(files, candidate) {
  candidate = withSuffix(candidate)
  if (!files[candidate]) return candidate

  const stem = candidate.slice(0, -".html.erb".length)
  let n = 2
  let next = `${stem}-${n}.html.erb`
  while (files[next]) {
    n += 1
    next = `${stem}-${n}.html.erb`
  }
  return next
}

// --- CRUD operations -- every one returns a NEW workspace object; none
// mutates the one it was given. ---

export function createFile(workspace, path) {
  const files = { ...workspace.files }
  const finalPath = uniquePath(files, path)
  files[finalPath] = { tree: { kind: "fragment", id: "root", children: [] } }
  return { ...workspace, files, open: finalPath }
}

export function createDirectory(workspace, path) {
  if (!path || workspace.directories.includes(path)) return workspace
  return { ...workspace, directories: [...workspace.directories, path] }
}

export function renameFile(workspace, oldPath, newPath) {
  if (!workspace.files[oldPath] || !newPath || oldPath === newPath) return workspace

  const files = { ...workspace.files }
  const finalPath = uniquePath(files, newPath)
  files[finalPath] = files[oldPath]
  delete files[oldPath]

  const open = workspace.open === oldPath ? finalPath : workspace.open
  return { ...workspace, files, open }
}

export function duplicateFile(workspace, path) {
  if (!workspace.files[path]) return workspace

  const files = { ...workspace.files }
  const copyPath = uniquePath(files, `${path.slice(0, -".html.erb".length)}-copy`)
  files[copyPath] = JSON.parse(JSON.stringify(files[path]))
  return { ...workspace, files, open: copyPath }
}

export function deleteFile(workspace, path) {
  if (!workspace.files[path]) return workspace

  const files = { ...workspace.files }
  delete files[path]
  const remaining = Object.keys(files).sort()
  const open = workspace.open === path ? (remaining[0] || null) : workspace.open
  return { ...workspace, files, open }
}

export function deleteDirectory(workspace, path) {
  const prefix = `${path}/`
  const files = {}
  Object.entries(workspace.files).forEach(([p, entry]) => {
    if (p !== path && !p.startsWith(prefix)) files[p] = entry
  })
  const directories = workspace.directories.filter((d) => d !== path && !d.startsWith(prefix))
  const open = workspace.open && files[workspace.open] ? workspace.open : (Object.keys(files).sort()[0] || null)
  return { ...workspace, files, directories, open }
}

export function setOpen(workspace, path) {
  if (!workspace.files[path]) return workspace
  return { ...workspace, open: path }
}

// --- Cross-file lookup ------------------------------------------------

// A `partial` node renders ANOTHER file's tree inline -- the elements it
// produces on the canvas carry `data-editor-node-id` values from THAT
// file's tree, not the open one (node ids are only guaranteed unique
// WITHIN one file -- the server's own duplicate-id validator scopes its
// check to a single tree). editor_controller.js needs to resolve such an
// id back to a real node (to show it read-only in the inspector, or to
// refuse a drag on it) without the server's help -- the client already
// holds every file's tree in `workspace.files`, so this is a pure,
// client-side search over that.
//
// Deliberately NOT in tree.js: that module is scoped to operating over ONE
// file's tree at a time and knows nothing about `path`/multi-file concerns
// (see its own header) -- this is exactly the kind of multi-file lookup
// this module already owns (createFile/renameFile/... above). It does
// reuse Tree.findNode per-file, though: that function's own contract
// ("search one tree for an id") holds unchanged here, just called once per
// candidate file instead of once overall.
//
// Search order: the OPEN file's own tree first, then -- only if not found
// there -- each `partial` node reachable from it, recursively, in document
// order. This is the correct tie-break precisely because ids are only
// file-scoped: if the open file happens to reuse an id that also exists in
// some included file, the open file's own node is what a click on it
// actually means.
//
// `visited` bounds the search to at most one visit per file, which is what
// keeps a legal A -> B -> A partial cycle from being an infinite recursion
// -- a plain "have I seen this id before" check has no natural stopping
// point (ids aren't visited, files are), so the bound has to be on paths,
// not on individual node visits.
//
// @return {node, path} -- `path` is the file the node actually lives in
//   (== openPath when it's a local hit), or null if `id` resolves nowhere
//   in the whole reachable workspace.
export function findNodeAcrossWorkspace(files, openPath, id) {
  const visited = new Set()

  function searchFile(path) {
    if (!path || visited.has(path) || !files[path]) return null
    visited.add(path)

    const tree = files[path].tree
    const node = Tree.findNode(tree, id)
    if (node) return { node, path }

    for (const partialPath of partialPaths(tree)) {
      const found = searchFile(partialPath)
      if (found) return found
    }
    return null
  }

  return searchFile(openPath)
}

// Every path a `partial` node inside `tree` references, in document order
// -- the edges #findNodeAcrossWorkspace's recursion follows into other
// files. A standalone walk rather than reusing tree.js's own childArrays
// (that helper isn't exported, and has no notion of a `partial` node's
// cross-file MEANING anyway -- it just knows which arrays hold children).
function partialPaths(node) {
  if (!node) return []
  const paths = []
  if (node.kind === "partial" && node.path) paths.push(node.path)

  if (Array.isArray(node.children)) node.children.forEach((child) => paths.push(...partialPaths(child)))
  if (node.slots && typeof node.slots === "object") {
    Object.values(node.slots).forEach((arr) => {
      if (Array.isArray(arr)) arr.forEach((child) => paths.push(...partialPaths(child)))
    })
  }
  if (Array.isArray(node.items)) node.items.forEach((child) => paths.push(...partialPaths(child)))

  return paths
}
