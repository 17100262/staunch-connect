import { Controller } from "@hotwired/stimulus"

// Filters a list of rows by the text typed into a search field.
export default class extends Controller {
  static targets = ["input", "item", "empty"]

  filter() {
    const q = this.inputTarget.value.trim().toLowerCase()
    let shown = 0
    this.itemTargets.forEach((item) => {
      const match = !q || item.dataset.name.toLowerCase().includes(q)
      item.hidden = !match
      if (match) shown++
    })
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = shown > 0
      const label = this.emptyTarget.querySelector("[data-query]")
      if (label) label.textContent = this.inputTarget.value.trim()
    }
  }
}
