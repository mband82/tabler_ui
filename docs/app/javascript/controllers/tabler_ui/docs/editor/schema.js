// Module-scope cache for GET /ui/editor/schema (Editor::Schema.as_json) --
// exactly docs/app/javascript/controllers/tabler_ui/docs/search_controller.js's
// own `fetchIndex` pattern, and for the same reason (see that file's header
// comment): the payload only changes when the server process restarts, but
// Turbo connects/disconnects Stimulus controllers on every page swap, so
// caching on `this` (or re-fetching in connect()) would re-download it on
// every single navigation to the editor instead of once. On failure the
// cache is reset to null so a transient error doesn't wedge the editor
// permanently -- the next attempt gets a fresh fetch, not a cached
// rejection.
let schemaPromise = null

export function fetchSchema(url) {
  if (!schemaPromise) {
    schemaPromise = fetch(url, { headers: { Accept: "application/json" } })
      .then((response) => {
        if (!response.ok) throw new Error(`schema request failed with status ${response.status}`)
        return response.json()
      })
      .catch((error) => {
        schemaPromise = null
        throw error
      })
  }
  return schemaPromise
}
