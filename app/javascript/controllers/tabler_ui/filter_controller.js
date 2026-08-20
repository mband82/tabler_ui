import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = {
    debounce: { type: Number, default: 200 },
    minChars: { type: Number, default: 0 }
  }

  connect() {
    this._debouncedSubmit = this._debounce(
      () => this._performSubmit(),
      this.debounceValue
    )
  }

  disconnect() {
    clearTimeout(this._timeout)
  }

  submit() {
    this._debouncedSubmit()
  }

  _performSubmit() {
    // Feature off: no threshold configured, or no search input to measure.
    // Behave exactly like the plain debounced submitter.
    if (this.minCharsValue <= 0 || !this.hasInputTarget) {
      this.element.requestSubmit()
      return
    }

    const value = this.inputTarget.value.trim()

    if (value.length === 0) {
      // Empty field always submits unfiltered, never blocked.
      this.inputTarget.classList.remove("is-invalid")
      this.element.requestSubmit()
      return
    }

    if (value.length < this.minCharsValue) {
      // Below threshold: show the hint (Bootstrap reveals .invalid-feedback
      // via the "~" sibling selector once the input carries .is-invalid),
      // but still submit so the URL/table fall back to the unfiltered state.
      this.inputTarget.classList.add("is-invalid")

      const original = this.inputTarget.value
      // Blanking, submitting, then restoring on the next line is safe even
      // though it looks like a race: requestSubmit() dispatches the "submit"
      // event synchronously, and both Turbo and the browser's native form
      // handling read/serialise the form's field values from inside that
      // same synchronous dispatch. By the time requestSubmit() returns, the
      // blank value has already been captured, so restoring the user's text
      // immediately afterwards cannot clobber what was sent.
      this.inputTarget.value = ""
      this.element.requestSubmit()
      this.inputTarget.value = original
      return
    }

    // At or above threshold: normal debounced submit.
    this.inputTarget.classList.remove("is-invalid")
    this.element.requestSubmit()
  }

  _debounce(fn, wait) {
    return (...args) => {
      clearTimeout(this._timeout)
      this._timeout = setTimeout(() => fn.apply(this, args), wait)
    }
  }
}
