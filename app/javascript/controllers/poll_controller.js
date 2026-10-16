import { Controller } from "@hotwired/stimulus"

// While a connector is syncing, reload the enclosing frame every few seconds so
// the status updates by itself. The `active` marker only exists while syncing.
export default class extends Controller {
  static targets = ["active"]

  connect() {
    if (!this.hasActiveTarget) return
    this.timer = setTimeout(() => this.element.closest("turbo-frame")?.reload(), 2500)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
