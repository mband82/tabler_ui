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
const PREFIX = "tabler-ui-docs-editor:"
export const WORKSPACE_KEY = `${PREFIX}workspace`
export const INDEX_KEY = `${PREFIX}index`

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
