// Stimulus controller for the navbar's Bootstrap-driven collapse. Applied
// directly to the collapsible element (the one Bootstrap's Collapse class
// acts on), not the toggler button. Lifecycle only: instantiate on connect,
// dispose on disconnect, so Turbo doesn't leak instances across reconnects.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const Bootstrap = window.tabler && window.tabler.bootstrap
    if (!Bootstrap) return

    this.collapse = new Bootstrap.Collapse(this.element, { toggle: false })
  }

  disconnect() {
    if (this.collapse) {
      this.collapse.dispose()
      this.collapse = null
    }
  }
}
