// Single shared HTML escaper for every editor module that builds markup as
// strings (explorer.js, palette.js, inspector.js, structure.js and
// editor_controller.js itself) -- rule 6 (CLAUDE.md): shared logic goes in
// a helper module rather than being copy-pasted between controllers/
// modules. Uses the DOM's own escaping (textContent -> innerHTML) rather
// than a hand-rolled regex, the same technique
// docs/app/javascript/controllers/tabler_ui/docs/search_controller.js's own
// `_escape` already relies on.
export function escapeHtml(value) {
  const div = document.createElement("div")
  div.textContent = value == null ? "" : String(value)
  return div.innerHTML
}
