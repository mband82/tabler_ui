import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { debounce: { type: Number, default: 200 } }

  connect() {
    this._debouncedSubmit = this._debounce(
      () => this.element.requestSubmit(),
      this.debounceValue
    )
  }

  disconnect() {
    clearTimeout(this._timeout)
  }

  submit() {
    this._debouncedSubmit()
  }

  _debounce(fn, wait) {
    return (...args) => {
      clearTimeout(this._timeout)
      this._timeout = setTimeout(() => fn.apply(this, args), wait)
    }
  }
}
