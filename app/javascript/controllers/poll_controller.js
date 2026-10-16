import { Controller } from "@hotwired/stimulus"

// While a connector is syncing, reload the enclosing frame (or the page) every few seconds so
// the status updates by itself. The `active` marker only exists while syncing.
export default class extends Controller {
  static targets = ["active"]

  connect() {
    if (!this.hasActiveTarget) return
    this.timer = setTimeout(() => {
      const frame = this.element.closest("turbo-frame")
      if (frame) frame.reload()
      else window.Turbo?.visit(window.location.href, { action: "replace" })
    }, 2500)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
