// Builds a downloadable zip of the whole design-editor workspace. Imported
// by editor_controller.js's #exportAll -- a plain ES module alongside
// tree.js/workspace.js, not a Stimulus controller and not a class (rule 6,
// CLAUDE.md: this file has no lifecycle and no DOM of its own to own).
//
// ## Deliberately ignorant of fetch/CSRF/DOM
//
// editor_controller.js already owns the one request primitive every file
// preview goes through (#_fetchPreview: the URL, the CSRF header, the
// { path, workspace } body, the { html, erb, workspace, errors } response
// shape -- see that method's own doc). Rather than duplicate any of that
// here, the caller hands in a `fetchPreview(path)` callback and this module
// never touches `fetch`, `this.csrfTokenValue`, or any DOM node itself.
//
// ## Sequential, not parallel, never through the AbortController
//
// One `fetchPreview` call at a time, awaited before the next starts --
// mirroring the existing (pre-zip) #exportAll's own `runNext` recursion.
// This must stay sequential and must never go through the debounced
// AbortController machinery `_sendPreview` uses for the LIVE preview (see
// editor_controller.js's own comment on `_fetchPreview`): an export in
// flight must never be cancelled by a live edit, and must never cancel one.
//
// ## In-zip paths get an "app/views/" prefix
//
// Workspace paths ("components/card/index.html.erb", the DEFAULT_PATH
// "index.html.erb" in editor/workspace.js) are keys into `workspace.files`
// only -- EditorController#preview (docs/app/controllers/tabler_ui/docs/
// editor_controller.rb) looks a path up directly in that Hash and never
// joins it against `app/views` or passes it to Rails' `render`. They are
// Rails view paths *relative to* app/views, not full repo paths. Since the
// zip is meant to unpack straight into a host app's own `app/views/`, this
// module adds that prefix itself -- it is not already present in the
// stored path.
//
// ## A file whose preview came back with errors
//
// Included in the zip anyway, with whatever ERB came back (matching the
// pre-zip #exportAll's own choice: `data.erb || "<%# ...errors... %>"`) --
// shipping a possibly-imperfect file beats silently dropping it from an
// otherwise-complete download with no trace anything was left out. Its
// path is also collected into `erroredPaths` so the caller can surface one
// combined warning naming every affected file through the existing
// `_renderErrors` channel.
const VIEWS_PREFIX = "app/views/"

export function zipEntryPath(workspacePath) {
  return `${VIEWS_PREFIX}${workspacePath}`
}

async function collectFiles(paths, fetchPreview) {
  const results = []
  // eslint-disable-next-line no-restricted-syntax
  for (const path of paths) {
    // eslint-disable-next-line no-await-in-loop -- deliberately sequential, see file header
    const result = await fetchPreview(path)
      .then((data) => ({
        path,
        erb: data.erb || `<%# ${(data.errors || []).join(", ")} %>`,
        errored: Boolean(data.errors && data.errors.length > 0)
      }))
      .catch((error) => ({ path, erb: `<%# request failed: ${error.message} %>`, errored: true }))
    results.push(result)
  }
  return results
}

// @param workspace {files: {...}} -- only the keys of `files` matter here;
//   each is both the lookup key passed to `fetchPreview` and (prefixed,
//   see #zipEntryPath) the path written into the zip.
// @param options.fetchPreview (path) => Promise<{erb, errors}> -- the
//   caller's existing request primitive; see this file's header.
// @return Promise<{blob, erroredPaths}> on success, or Promise<{error}> if
//   the zip could not be built at all (JSZip failed to load, or
//   `generateAsync` itself rejected). Never throws and never rejects --
//   every failure mode resolves to one of these two shapes so the caller
//   can render it without wrapping this call in its own try/catch (chart_
//   controller.js's dynamic-import-with-.catch discipline, applied to a
//   plain async function instead of a Stimulus `connect()`).
export async function exportWorkspaceZip(workspace, { fetchPreview }) {
  const paths = Object.keys((workspace && workspace.files) || {})
  const results = await collectFiles(paths, fetchPreview)

  let zipModule
  try {
    // Only ever called here, on demand (editor_controller.js's #exportAll
    // fires it on a click) -- never in connect() -- so no other docs page
    // pays for JSZip loading. See docs/config/importmap.rb's
    // "tabler_ui/docs/jszip" pin (esm.sh, not a raw jsDelivr file: JSZip
    // itself only ships CommonJS, and esm.sh is what wraps it into a real
    // ES module with a genuine `export default`).
    zipModule = await import("tabler_ui/docs/jszip")
  } catch (error) {
    return { error: `could not load the zip library: ${error.message}` }
  }

  const JSZip = zipModule && zipModule.default
  if (typeof JSZip !== "function") {
    return { error: "zip library loaded but its default export is not a constructor" }
  }

  const zip = new JSZip()
  const erroredPaths = []
  results.forEach(({ path, erb, errored }) => {
    // JSZip creates intermediate folder entries implicitly from a "/" in
    // the path passed to #file -- no separate #folder call needed to get
    // real nested directories back out on unzip.
    zip.file(zipEntryPath(path), erb)
    if (errored) erroredPaths.push(path)
  })

  try {
    const blob = await zip.generateAsync({ type: "blob" })
    return { blob, erroredPaths }
  } catch (error) {
    return { error: `could not build the zip: ${error.message}` }
  }
}
