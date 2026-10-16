import { Controller } from "@hotwired/stimulus"

// Several named in-page dialogs on one page. A trigger passes the name:
// data-action="dialogs#open" data-dialogs-name-param="export".
export default class extends Controller {
  static targets = ["scrim"]

  open(event) {
    event.preventDefault()
    this.previous = document.activeElement
    this.current = this.scrimTargets.find((s) => s.dataset.name === event.params.name)
    if (!this.current) return
    this.current.hidden = false
    this.current.querySelector("input:not([type=hidden]), button")?.focus()
    this.onKey = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKey)
  }

  close(event) {
    event?.preventDefault()
    if (this.current) this.current.hidden = true
    document.removeEventListener("keydown", this.onKey)
    this.previous?.focus()
  }

  closeSoon() { setTimeout(() => this.close(), 150) }

  backdrop(event) {
    if (event.target === this.current) this.close()
  }

  disconnect() { document.removeEventListener("keydown", this.onKey) }
}
