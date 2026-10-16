import { Controller } from "@hotwired/stimulus"

// Submits a form shortly after the person stops typing (live search).
export default class extends Controller {
  queue() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), 250)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
