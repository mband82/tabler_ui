// Stimulus controller for Bootstrap-driven tabs / list-group tabs.
// Bootstrap's Tab class backs both data-bs-toggle="tab" (tabs component) and
// data-bs-toggle="list" (settings_page component) -- this controller wraps
// it for either. Lifecycle only: instantiate on connect, dispose on
// disconnect, so Turbo doesn't leak instances across reconnects.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    const Bootstrap = window.tabler && window.tabler.bootstrap
    if (!Bootstrap || !this.hasToggleTarget) return

    // tabler.js activates a Tab (calling .show()) for whichever tab matches
    // window.location.hash at import time, which instantiates it. Adopt any
    // pre-existing instance per element rather than constructing a
    // competing one -- see alert_controller.js for why. Track per-element
    // ownership so disconnect() only disposes the ones we created.
    this.instances = this.toggleTargets.map((el) => ({
      owns: !Bootstrap.Tab.getInstance(el),
      tab: Bootstrap.Tab.getOrCreateInstance(el)
    }))
  }

  disconnect() {
    if (!this.instances) return

    this.instances.forEach(({ tab, owns }) => {
      if (owns) tab.dispose()
    })
    this.instances = null
  }
}
