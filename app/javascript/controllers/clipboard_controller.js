import { Controller } from "@hotwired/stimulus"

// Copies text to the clipboard and briefly swaps a copy icon for a check.
export default class extends Controller {
  static values = { text: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
    } catch (e) {
      return
    }
    const use = this.element.querySelector('use[href="#i-copy"]')
    if (!use) return
    use.setAttribute("href", "#i-check")
    setTimeout(() => use.setAttribute("href", "#i-copy"), 1500)
  }
}
