import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]
  static values = {
    color: { type: String, default: "primary" }
  }

  connect() {
    this.updateAppearance()
  }

  toggle() {
    if (!this.hasInputTarget) return

    const checked = this.inputTarget.value === "1"
    this.inputTarget.value = checked ? "0" : "1"
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.updateAppearance()
  }

  updateAppearance() {
    if (!this.hasInputTarget || !this.hasButtonTarget) return

    const checked = this.inputTarget.value === "1"
    const btn = this.buttonTarget
    const color = this.colorValue

    btn.classList.remove(`btn-${color}`, `btn-outline-${color}`)
    btn.classList.add(checked ? `btn-${color}` : `btn-outline-${color}`)
  }
}
