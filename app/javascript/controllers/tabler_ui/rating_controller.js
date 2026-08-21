// Stimulus controller for Star Rating component
// Uses star-rating.js library to transform select inputs into star ratings
//
// IMPORTANT: this controller must stay on a wrapper <span> around the
// <select>, never on the <select> itself. star-rating.js reparents the
// <select> it's given (see buildWidget/destroy in
// app/assets/javascripts/star-rating.js) -- it moves it into a wrapper span
// it creates, and moves it back out again on destroy(). If the Stimulus
// controller lived on the <select>, Stimulus's DOM observer would see each
// of those moves as "element removed, then a different element added" and
// fire disconnect()/connect() for it -- disconnect() tears the widget down
// (another reparent), which triggers another connect() that rebuilds it
// (another reparent), forever. That connect/mutate/disconnect/mutate loop
// has no thrown error, so it just pegs the main thread and hangs the tab.
// See TablerUi::Rating::Component#wrapper_attributes for the full writeup.
// Because of this, the library is also pointed at the <select> via the
// `select` target below, not a `document.querySelectorAll` id selector --
// querying by selector would still find and move the same element either way.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select"]

  static values = {
    tooltip: { type: Boolean, default: true },
    clearable: { type: Boolean, default: true },
    color: String,
    size: String
  }

  connect() {
    import("star-rating.js").then((module) => {
      if (typeof module.default !== "function") {
        console.error("star-rating.js loaded but its default export is not a constructor -- the vendored file may be missing its `export default StarRating` line")
        return
      }

      this.StarRating = module.default
      this.initRating()
    }).catch((error) => {
      console.error("Failed to load star-rating.js:", error)
    })
  }

  initRating() {
    if (!this.StarRating) {
      console.warn("StarRating library not loaded")
      return
    }

    if (!this.hasSelectTarget) {
      console.warn("tabler-ui--rating: no select target found")
      return
    }

    const options = {
      tooltip: this.tooltipValue,
      clearable: this.clearableValue,
      stars: this.getStarsFunction()
    }

    if (this.colorValue) {
      options.variant = this.colorValue
    }

    if (this.sizeValue) {
      options.size = this.sizeValue
    }

    this.rating = new this.StarRating(this.selectTarget, options)
  }

  getStarsFunction() {
    return (el, item, index) => {
      let iconClass = "icon gl-star-full"

      if (this.sizeValue) {
        iconClass += ` icon-${this.sizeValue}`
      } else {
        iconClass += " icon-2"
      }

      if (this.colorValue) {
        iconClass += ` text-${this.colorValue}`
      }

      el.innerHTML = this.getStarSvg(iconClass)
    }
  }

  getStarSvg(iconClass) {
    return `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor" class="${iconClass}"><path d="M8.243 7.34l-6.38 .925l-.113 .023a1 1 0 0 0 -.44 1.684l4.622 4.499l-1.09 6.355l-.013 .11a1 1 0 0 0 1.464 .944l5.706 -3l5.693 3l.1 .046a1 1 0 0 0 1.352 -1.1l-1.091 -6.355l4.624 -4.5l.078 -.085a1 1 0 0 0 -.633 -1.62l-6.38 -.926l-2.852 -5.78a1 1 0 0 0 -1.794 0l-2.853 5.78z" /></svg>`
  }

  disconnect() {
    if (this.rating && typeof this.rating.destroy === "function") {
      this.rating.destroy()
    }
  }
}
