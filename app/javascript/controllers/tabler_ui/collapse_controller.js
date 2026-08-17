// Stimulus controller for the navbar's Bootstrap-driven collapse. Applied
// directly to the collapsible element (the one Bootstrap's Collapse class
// acts on), not the toggler button. Lifecycle only: instantiate on connect,
// dispose on disconnect, so Turbo doesn't leak instances across reconnects.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const Bootstrap = window.tabler && window.tabler.bootstrap
    if (!Bootstrap) return

    // Adopt an existing instance rather than constructing a competing one --
    // see alert_controller.js for why. Note that getOrCreateInstance only
    // applies the `{ toggle: false }` option when it actually creates the
    // instance; an adopted instance keeps whatever config it was made with,
    // which is correct here.
    this.ownsCollapse = !Bootstrap.Collapse.getInstance(this.element)
    this.collapse = Bootstrap.Collapse.getOrCreateInstance(this.element, { toggle: false })
  }

  disconnect() {
    if (this.collapse && this.ownsCollapse) {
      this.collapse.dispose()
    }
    this.collapse = null
    this.ownsCollapse = false
  }
}
