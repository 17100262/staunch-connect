import { Controller } from "@hotwired/stimulus"

// Dismisses a toast after a few seconds.
export default class extends Controller {
  connect() { this.timer = setTimeout(() => this.element.remove(), 5000) }
  disconnect() { clearTimeout(this.timer) }
}
