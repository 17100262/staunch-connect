import { Controller } from "@hotwired/stimulus"

// Underline tabs that switch between panels. Each tab and panel carries data-panel.
export default class extends Controller {
  static targets = ["tab", "panel"]

  select(event) {
    const key = event.currentTarget.dataset.panel
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-selected", String(tab.dataset.panel === key)))
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.panel !== key })
  }
}
