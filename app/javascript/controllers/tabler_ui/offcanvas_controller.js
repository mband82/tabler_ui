// Stimulus controller for the Bootstrap-driven offcanvas. Applied directly to
// the `.offcanvas` element itself (the one Bootstrap's Offcanvas class acts
// on), not the toggler button -- the component renders no trigger, callers
// put data-bs-toggle="offcanvas" data-bs-target="#<id>" on their own button.
// Note tabler.js does not auto-instantiate Offcanvas, so this controller is
// what actually creates the Bootstrap.Offcanvas instance. Lifecycle only:
// instantiate on connect, dispose on disconnect, so Turbo doesn't leak
// instances across reconnects.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const Bootstrap = window.tabler && window.tabler.bootstrap
    if (!Bootstrap) return

    // Adopt an existing instance rather than constructing a competing one --
    // see collapse_controller.js / alert_controller.js for why. A host app
    // that instantiated its own Offcanvas on this element first keeps
    // ownership; this controller only disposes instances it created itself.
    this.ownsOffcanvas = !Bootstrap.Offcanvas.getInstance(this.element)
    this.offcanvas = Bootstrap.Offcanvas.getOrCreateInstance(this.element)
  }

  disconnect() {
    if (this.offcanvas && this.ownsOffcanvas) {
      this.offcanvas.dispose()
    }
    this.offcanvas = null
    this.ownsOffcanvas = false
  }
}
