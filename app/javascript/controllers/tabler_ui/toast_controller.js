// Stimulus controller for the Bootstrap-driven toast. Applied directly to
// the `.toast` element itself (the one Bootstrap's Toast class acts on), not
// a trigger button -- the component renders no trigger, callers put
// data-bs-toggle="toast" data-bs-target="#<id>" on their own button, exactly
// like Bootstrap's own docs.
//
// Unlike modal, tabler.js *does* auto-instantiate toasts: at import time it
// scans the DOM once for `[data-bs-toggle="toast"]` triggers carrying
// data-bs-target, does `new Toast(target)` on each match, and binds a click
// listener on the trigger to call `.show()` (see
// app/assets/javascripts/tabler_ui/tabler.js, the "Toasts" block, ~line
// 6223). That means an instance may already exist on this element by the
// time this controller connects -- getOrCreateInstance() adopts it instead
// of constructing a competing one, and the ownership flag makes sure
// disconnect() only disposes an instance this controller itself created.
//
// This controller deliberately does NOT bind its own click listener to any
// trigger: doing so would double-invoke `.show()` on every click for a
// trigger tabler.js's one-time scan already bound (an existing Toast opened
// twice). It also does not call `.show()` in connect() -- that would break
// the common "hidden until triggered" pattern (a toast sitting in the DOM,
// shown later by a `data-bs-toggle="toast"` click) by showing every toast
// immediately on render. The tradeoff: a trigger/toast pair inserted into
// the DOM *after* tabler.js has already run its one-time scan (e.g. via a
// Turbo Stream) won't get that automatic click wiring -- tabler.js has no
// MutationObserver, only the initial scan. A caller in that situation shows
// the toast itself, e.g. another controller/action calling
// `Bootstrap.Toast.getOrCreateInstance(el).show()`. Lifecycle only here,
// same as modal_controller.js / alert_controller.js.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const Bootstrap = window.tabler && window.tabler.bootstrap
    if (!Bootstrap) return

    // Adopt an existing instance (very possibly created by tabler.js's own
    // auto-init scan, see above) rather than constructing a competing one --
    // see modal_controller.js / alert_controller.js for the general pattern.
    // This controller only disposes instances it created itself.
    this.ownsToast = !Bootstrap.Toast.getInstance(this.element)
    this.toast = Bootstrap.Toast.getOrCreateInstance(this.element)
  }

  disconnect() {
    if (this.toast && this.ownsToast) {
      this.toast.dispose()
    }
    this.toast = null
    this.ownsToast = false
  }
}
