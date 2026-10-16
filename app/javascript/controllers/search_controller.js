import { Controller } from "@hotwired/stimulus"

// Opens the global search dialog from the rail's search field or Ctrl/Cmd K.
export default class extends Controller {
  static targets = ["scrim", "field"]

  open() {
    this.scrimTarget.hidden = false
    this.fieldTarget.focus()
  }

  close() {
    this.scrimTarget.hidden = true
  }

  backdrop(event) {
    if (event.target === this.scrimTarget) this.close()
  }

  shortcut(event) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.scrimTarget.hidden ? this.open() : this.close()
    }
  }
}
