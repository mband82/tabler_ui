// Stimulus controller for the alert component's Bootstrap-driven dismiss.
// Applied to the root .alert element -- the one Bootstrap's Alert class
// acts on, not the dismiss button itself. Lifecycle only: instantiate on
// connect, dispose on disconnect, so Turbo doesn't leak instances across
// reconnects.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const Bootstrap = window.tabler && window.tabler.bootstrap
    if (!Bootstrap) return

    this.alert = new Bootstrap.Alert(this.element)
  }

  disconnect() {
    if (this.alert) {
      this.alert.dispose()
      this.alert = null
    }
  }
}
