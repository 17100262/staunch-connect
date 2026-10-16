import { Controller } from "@hotwired/stimulus"

// On narrow screens the chat list is hidden; the header's list button shows it over the chat.
export default class extends Controller {
  toggle() {
    this.element.toggleAttribute("data-list-open")
  }
}
