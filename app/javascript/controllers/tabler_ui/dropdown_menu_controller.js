// Stimulus controller for Bootstrap-driven dropdowns. Applied directly to
// the toggle element (the one with data-bs-toggle="dropdown"), used by both
// the dropdown component and navbar's dropdown nav items. Lifecycle only:
// instantiate on connect, dispose on disconnect, so Turbo doesn't leak
// instances across reconnects.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const Bootstrap = window.tabler && window.tabler.bootstrap
    if (!Bootstrap) return

    // tabler.js unconditionally instantiates a Dropdown on every
    // [data-bs-toggle="dropdown"] element at import time, passing a
    // `boundary` option derived from data-bs-boundary. Adopt that instance
    // instead of constructing a second one -- a bare `new` here would both
    // orphan tabler.js's instance and drop its boundary option, since
    // getOrCreateInstance only applies options when it actually creates.
    this.ownsDropdown = !Bootstrap.Dropdown.getInstance(this.element)
    this.dropdown = Bootstrap.Dropdown.getOrCreateInstance(this.element)
  }

  disconnect() {
    if (this.dropdown && this.ownsDropdown) {
      this.dropdown.dispose()
    }
    this.dropdown = null
    this.ownsDropdown = false
  }
}
