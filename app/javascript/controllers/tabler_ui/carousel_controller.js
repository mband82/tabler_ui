// Stimulus controller for the Bootstrap-driven carousel. Applied directly to
// the `.carousel` element itself (the one Bootstrap's Carousel class acts
// on). tabler.js's own carousel data-api only auto-instantiates elements
// matching `[data-bs-ride="carousel"]`, and only on the `window`'s `load`
// event -- see the "Data API implementation" block in
// `app/assets/javascripts/tabler_ui/tabler.js` (`carousel.js`). That event
// fires once per full page load and never again, so a carousel inserted (or
// reconnected) via Turbo after that point -- most of them, in practice --
// would never get autoplay, keyboard, wrap, or interval config picked up
// from its `data-bs-*` attributes without a hand-rolled `new
// Bootstrap.Carousel(el)`. This controller is that lifecycle glue: it reads
// no config of its own (Bootstrap already parses `data-bs-interval` /
// `data-bs-wrap` / `data-bs-keyboard` / `data-bs-ride` straight off the
// element), and instantiate-on-connect/dispose-on-disconnect keeps Turbo
// from leaking instances across reconnects. Same ownership pattern as
// modal_controller.js -- see there for why.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const Bootstrap = window.tabler && window.tabler.bootstrap
    if (!Bootstrap) return

    // Adopt an existing instance rather than constructing a competing one --
    // see modal_controller.js / collapse_controller.js for why. A host app
    // (or Bootstrap's own load-time data-api, if this connects before that
    // event fires) that instantiated Carousel on this element first keeps
    // ownership; this controller only disposes instances it created itself.
    this.ownsCarousel = !Bootstrap.Carousel.getInstance(this.element)
    this.carousel = Bootstrap.Carousel.getOrCreateInstance(this.element)
  }

  disconnect() {
    if (this.carousel && this.ownsCarousel) {
      this.carousel.dispose()
    }
    this.carousel = null
    this.ownsCarousel = false
  }
}
