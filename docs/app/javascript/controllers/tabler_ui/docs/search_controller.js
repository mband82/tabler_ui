import { Controller } from "@hotwired/stimulus"

// Module-scope cache: fetched once per page load, shared by every
// connected instance of this controller. Turbo connects/disconnects
// Stimulus controllers on every visit that swaps the page, but the
// index's content only changes when the server process restarts (see
// docs/lib/tabler_ui/docs/search_index.rb's "Caching" section) -- storing
// the fetch promise on `this` or re-fetching in connect() would
// re-download the whole index (currently ~170KB of JSON) on every single
// page navigation instead of once.
let indexPromise = null

function fetchIndex(url) {
  if (!indexPromise) {
    indexPromise = fetch(url, { headers: { Accept: "application/json" } })
      .then((response) => response.json())
      .catch((error) => {
        // A failed fetch must not permanently wedge every later search --
        // let the next attempt retry instead of caching a rejection.
        indexPromise = null
        throw error
      })
  }
  return indexPromise
}

const KIND_LABELS = {
  component: "Component",
  section: "Section",
  option: "Option",
  example: "Example",
  demo: "Demo"
}

const MAX_RESULTS = 50

// Full-text search box for the docs engine. Fetches
// TablerUi::Docs::SearchIndex, served as JSON from `urlValue` (see
// docs/app/controllers/tabler_ui/docs/search_controller.rb), once, and
// filters it entirely client-side on every keystroke -- no server
// round-trip per search.
//
// Three rules this controller must never break -- each one is a bug this
// codebase already shipped and fixed once, in the table component's own
// filter toolbar (see app/components/tabler_ui/table/component.rb's "##
// Filtering" section and app/javascript/controllers/tabler_ui/filter_controller.js):
//
//   1. Debounce the input. Even entirely client-side, re-filtering on
//      every single keystroke flashes the result list.
//   2. Never trap the user. Clearing the field (or dropping back below
//      minLengthValue) always, immediately, returns to the empty/hidden
//      state -- never debounced, never dependent on a pending fetch or a
//      still-in-flight previous search. There is no threshold with no
//      escape.
//   3. NEVER re-render the element being typed into. The `input` target
//      is only ever read here (`this.inputTarget.value`) -- nothing in
//      this controller writes to it, replaces it, or re-renders any
//      ancestor that contains it. Every DOM write lands on the separate
//      `results` target, a sibling of `input`, not a wrapper around it.
//      This is the one that actually bit us elsewhere: an auto-submitting
//      filter without a Turbo Frame stole focus mid-typing and scrolled
//      the page back to the top on every debounced submit.
export default class extends Controller {
  static targets = ["input", "results"]
  static values = {
    url: { type: String, default: "" },
    debounce: { type: Number, default: 150 },
    minLength: { type: Number, default: 2 }
  }

  disconnect() {
    if (this._timeout) clearTimeout(this._timeout)
    this._timeout = null
  }

  // data-action="input->tabler-ui--docs-search#search" on the input
  // target itself.
  search() {
    if (this._timeout) clearTimeout(this._timeout)

    const query = this.hasInputTarget ? this.inputTarget.value.trim() : ""

    if (query.length < this.minLengthValue) {
      // Lesson 2: resolved synchronously, no debounce -- clearing the
      // field can never be left waiting behind a stale timer or a
      // still-loading index.
      this._render([], query)
      return
    }

    // Lesson 1: everything else is debounced.
    this._timeout = setTimeout(() => this._performSearch(query), this.debounceValue)
  }

  _performSearch(query) {
    fetchIndex(this.urlValue)
      .then((entries) => this._render(this._filter(entries, query), query))
      .catch(() => this._render([], query))
  }

  _filter(entries, query) {
    const needle = query.toLowerCase()

    return entries
      .filter((entry) => (
        (entry.label && entry.label.toLowerCase().includes(needle)) ||
        (entry.component && entry.component.toLowerCase().includes(needle)) ||
        (entry.context && entry.context.toLowerCase().includes(needle))
      ))
      .slice(0, MAX_RESULTS)
  }

  // Lesson 3: the only method in this controller that writes to the DOM,
  // and it only ever touches `results` -- never `input`, never an
  // ancestor of `input`.
  _render(matches, query) {
    if (!this.hasResultsTarget) return

    if (query.length < this.minLengthValue) {
      this.resultsTarget.hidden = true
      this.resultsTarget.innerHTML = ""
      return
    }

    this.resultsTarget.hidden = false

    if (matches.length === 0) {
      this.resultsTarget.innerHTML =
        `<div class="list-group-item text-secondary">No results for "${this._escape(query)}"</div>`
      return
    }

    this.resultsTarget.innerHTML = matches.map((entry) => this._resultHtml(entry)).join("")
  }

  _resultHtml(entry) {
    const href = entry.anchor ? `${entry.path}#${entry.anchor}` : entry.path
    const kind = KIND_LABELS[entry.kind] || entry.kind

    return `
      <a class="list-group-item list-group-item-action" href="${this._escape(href)}">
        <div class="d-flex justify-content-between align-items-center">
          <span>${this._escape(entry.label)}</span>
          <span class="badge bg-secondary-lt text-secondary ms-2">${this._escape(kind)}</span>
        </div>
        <div class="text-secondary small">${this._escape(entry.context || "")}</div>
      </a>
    `
  }

  _escape(value) {
    const div = document.createElement("div")
    div.textContent = value == null ? "" : String(value)
    return div.innerHTML
  }
}
