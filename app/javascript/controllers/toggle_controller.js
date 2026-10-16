import { Controller } from "@hotwired/stimulus"

// Shows or hides its `panel` targets and keeps aria-expanded on the trigger in step.
export default class extends Controller {
  static targets = ["panel", "trigger"]

  toggle(event) {
    event?.preventDefault()
    const open = this.panelTargets.some((p) => p.hidden)
    this.panelTargets.forEach((p) => { p.hidden = !open })
    this.triggerTargets.forEach((t) => t.setAttribute("aria-expanded", String(open)))
  }

  outside(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  hide() {
    this.panelTargets.forEach((p) => { p.hidden = true })
    this.triggerTargets.forEach((t) => t.setAttribute("aria-expanded", "false"))
  }
}
