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

    // Adopt an instance tabler.js (or another controller) may already have
    // created for this element rather than constructing a competing one --
    // Bootstrap only keeps one instance per element per component key, so a
    // bare `new` here would silently orphan the existing instance. Note
    // whether we created it so disconnect() only disposes what we own.
    this.ownsAlert = !Bootstrap.Alert.getInstance(this.element)
    this.alert = Bootstrap.Alert.getOrCreateInstance(this.element)
  }

  disconnect() {
    if (this.alert && this.ownsAlert) {
      this.alert.dispose()
    }
    this.alert = null
    this.ownsAlert = false
  }
}
