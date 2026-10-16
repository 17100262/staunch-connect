import { Controller } from "@hotwired/stimulus"

// "Check the setup" step: inline editors for billing cycle and rate, and the
// Hubstaff project dialog that feeds the form's hidden field.
export default class extends Controller {
  static targets = ["hubDialog", "hubField", "hubName", "hubBadge", "hubRow", "hubFilter",
    "monthEditor", "monthLabel", "monthSelect", "rateEditor", "rateInput", "rateLabel", "rateError", "rateField", "build"]

  static values = { matched: String }

  toggleMonth() { this.monthEditorTarget.hidden = !this.monthEditorTarget.hidden }
  toggleRate() { this.rateEditorTarget.hidden = !this.rateEditorTarget.hidden }

  changeMonth() {
    const select = this.monthSelectTarget
    this.monthLabelTarget.textContent = select.options[select.selectedIndex].text
  }

  changeRate() {
    const value = this.rateInputTarget.value.trim()
    const ok = /^\d+(\.\d+)?$/.test(value) && parseFloat(value) > 0
    this.rateErrorTarget.hidden = ok
    this.rateEditorTarget.querySelector(".input").setAttribute("aria-invalid", String(!ok))
    this.buildTarget.disabled = !ok
    if (ok) {
      this.rateFieldTarget.value = value
      this.rateLabelTarget.textContent = `$${parseFloat(value).toFixed(2)}`
    }
  }

  openHub(event) {
    event.preventDefault()
    this.hubDialogTarget.hidden = false
    this.hubFilterTarget.focus()
  }

  closeHub(event) {
    event?.preventDefault()
    this.hubDialogTarget.hidden = true
  }

  hubBackdrop(event) {
    if (event.target === this.hubDialogTarget) this.closeHub()
  }

  useHub(event) {
    event.preventDefault()
    const picked = this.hubDialogTarget.querySelector("input[name=hub_pick]:checked")
    if (!picked) return
    this.hubFieldTarget.value = picked.value
    const none = picked.value === "none"
    this.hubNameTarget.textContent = none ? "Not compared" : picked.dataset.label
    const state = none ? "none" : (picked.value === this.matchedValue ? "matched" : "chosen")
    const tones = { none: "warning", matched: "success", chosen: "neutral" }
    const texts = { none: "Not compared", matched: "Matched", chosen: "Chosen" }
    this.hubBadgeTarget.dataset.tone = tones[state]
    this.hubBadgeTarget.textContent = texts[state]
    this.closeHub()
  }

  filterHub() {
    const q = this.hubFilterTarget.value.trim().toLowerCase()
    this.hubRowTargets.forEach((row) => { row.hidden = q && !row.dataset.name.toLowerCase().includes(q) })
  }

  syncHubRows() {
    this.hubRowTargets.concat(Array.from(this.hubDialogTarget.querySelectorAll("[data-hub-none]"))).forEach((row) => {
      const input = row.querySelector("input")
      row.setAttribute("aria-current", String(input.checked))
    })
  }
}
