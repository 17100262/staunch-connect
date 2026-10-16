import { Controller } from "@hotwired/stimulus"

// Single choice from a list of radio rows, or several from checkbox rows.
// Marks selected rows, keeps a count, fills a name field and gates the submit button.
export default class extends Controller {
  static targets = ["row", "submit", "count", "name"]

  connect() { this.sync() }

  sync() {
    let selected = 0
    let lastLabel = ""
    this.rowTargets.forEach((row) => {
      const input = row.querySelector("input")
      row.setAttribute("aria-selected", input.checked ? "true" : "false")
      if (input.checked) { selected++; lastLabel = input.dataset.label || "" }
    })
    if (this.hasSubmitTarget) this.submitTarget.disabled = selected === 0
    if (this.hasCountTarget) this.countTarget.textContent = `${selected} selected`
    if (this.hasNameTarget) this.nameTarget.value = lastLabel
  }
}
