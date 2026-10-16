import { Controller } from "@hotwired/stimulus"

// Swaps a title for a small form (rename), and back.
export default class extends Controller {
  static targets = ["view", "form", "input"]

  start() {
    this.viewTarget.hidden = true
    this.formTarget.hidden = false
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  cancel() {
    this.inputTarget.value = this.inputTarget.defaultValue
    this.formTarget.hidden = true
    this.viewTarget.hidden = false
  }
}
