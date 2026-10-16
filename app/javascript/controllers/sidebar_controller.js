import { Controller } from "@hotwired/stimulus"

// Collapses the rail sidebar to icons only. Remembers the choice per browser.
export default class extends Controller {
  static targets = ["rail", "toggle", "toggleTip"]

  connect() {
    let collapsed = false
    try { collapsed = localStorage.getItem("sc.rail") === "collapsed" } catch (e) {}
    this.apply(collapsed)
  }

  toggle() {
    const collapsed = !this.railTarget.hasAttribute("data-collapsed")
    this.apply(collapsed)
    try { localStorage.setItem("sc.rail", collapsed ? "collapsed" : "expanded") } catch (e) {}
  }

  apply(collapsed) {
    this.railTarget.toggleAttribute("data-collapsed", collapsed)
    if (collapsed) this.element.setAttribute("data-rail", "collapsed")
    else this.element.removeAttribute("data-rail")
    const label = collapsed ? "Expand sidebar" : "Collapse sidebar"
    this.toggleTarget.setAttribute("aria-label", label)
    this.toggleTipTarget.textContent = label
  }
}
