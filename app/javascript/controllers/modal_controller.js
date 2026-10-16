import { Controller } from "@hotwired/stimulus"

// A dialog loaded into the `modal` Turbo Frame (e.g. the new-invoice setup).
// Closing empties the frame. Esc and a click on the scrim also close it.
export default class extends Controller {
  connect() {
    this.onKey = (event) => { if (event.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKey)
    this.previous = document.activeElement
    const focusable = this.element.querySelector("input:not([type=hidden]), button, a[href]")
    focusable?.focus()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    if (this.previous && document.contains(this.previous)) this.previous.focus()
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  close(event) {
    event?.preventDefault()
    const frame = this.element.closest("turbo-frame")
    if (frame) {
      frame.removeAttribute("src")
      frame.replaceChildren()
    } else {
      this.element.hidden = true
    }
  }
}
