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

    this.instances = this.toggleTargets.map((el) => new Bootstrap.Tab(el))
  }

  disconnect() {
    if (!this.instances) return

    this.instances.forEach((instance) => instance.dispose())
    this.instances = null
  }
}
