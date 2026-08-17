// Stimulus controller for the Bootstrap-driven modal. Applied directly to
// the `.modal` element itself (the one Bootstrap's Modal class acts on), not
// the toggler button -- the component renders no trigger, callers put
// data-bs-toggle="modal" data-bs-target="#<id>" on their own button. Note
// tabler.js does not auto-instantiate Modal, so this controller is what
// actually creates the Bootstrap.Modal instance. Lifecycle only: instantiate
// on connect, dispose on disconnect, so Turbo doesn't leak instances across
// reconnects.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const Bootstrap = window.tabler && window.tabler.bootstrap
    if (!Bootstrap) return

    // Adopt an existing instance rather than constructing a competing one --
    // see collapse_controller.js / alert_controller.js for why. A host app
    // that instantiated its own Modal on this element first keeps ownership;
    // this controller only disposes instances it created itself.
    this.ownsModal = !Bootstrap.Modal.getInstance(this.element)
    this.modal = Bootstrap.Modal.getOrCreateInstance(this.element)
  }

  disconnect() {
    if (this.modal && this.ownsModal) {
      this.modal.dispose()
    }
    this.modal = null
    this.ownsModal = false
  }
}
