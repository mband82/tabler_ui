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

    this.dropdown = new Bootstrap.Dropdown(this.element)
  }

  disconnect() {
    if (this.dropdown) {
      this.dropdown.dispose()
      this.dropdown = null
    }
  }
}
