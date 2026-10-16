import { Controller } from "@hotwired/stimulus"

// Click-to-rename for the invoice title. Enter keeps the name, Esc cancels.
export default class extends Controller {
  static targets = ["display", "editor", "input", "label", "badge"]

  start() {
    this.original = this.inputTarget.value
    this.displayTarget.hidden = true
    this.badgeTargets.forEach((b) => { b.hidden = true })
    this.editorTarget.hidden = false
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  finish() {
    const value = this.inputTarget.value.trim() || this.original
    this.inputTarget.value = value
    this.labelTarget.textContent = value
    this.editorTarget.hidden = true
    this.displayTarget.hidden = false
    this.badgeTargets.forEach((b) => { b.hidden = false })
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  key(event) {
    if (event.key === "Enter") { event.preventDefault(); this.finish() }
    if (event.key === "Escape") { event.preventDefault(); this.inputTarget.value = this.original; this.finish() }
  }
}
