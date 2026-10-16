import { Controller } from "@hotwired/stimulus"

// Chat composer: auto-growing textarea (max 160px); Enter sends, Shift+Enter adds a line.
export default class extends Controller {
  static targets = ["field"]

  grow() {
    this.fieldTarget.style.height = "auto"
    this.fieldTarget.style.height = `${Math.min(this.fieldTarget.scrollHeight, 160)}px`
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
    event.preventDefault()
    if (this.fieldTarget.value.trim()) this.element.requestSubmit()
  }
}
