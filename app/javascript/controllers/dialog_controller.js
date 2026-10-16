import { Controller } from "@hotwired/stimulus"

// In-page dialogs (delete confirm, export). The scrim starts hidden; open/close toggle it.
export default class extends Controller {
  static targets = ["scrim"]

  open(event) {
    event?.preventDefault()
    this.scrimTarget.hidden = false
    this.previous = document.activeElement
    this.onKey = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKey)
    this.scrimTarget.querySelector("input:not([type=hidden]), button")?.focus()
  }

  close(event) {
    event?.preventDefault()
    this.scrimTarget.hidden = true
    document.removeEventListener("keydown", this.onKey)
    this.previous?.focus()
  }

  backdrop(event) {
    if (event.target === this.scrimTarget) this.close()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
  }
}
