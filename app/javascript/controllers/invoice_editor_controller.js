import { Controller } from "@hotwired/stimulus"

// Editable invoice: recalculates amounts and totals as estimate, rate or the
// bill checkbox change, validates numbers, and enables Save only when dirty and valid.
export default class extends Controller {
  static targets = ["row", "est", "rate", "bill", "amount", "name", "save", "total", "totalHours", "billedCount", "badge", "errorAlert", "statEst", "statTotal", "statCount"]

  connect() {
    this.initial = this.snapshot()
    this.recalc()
  }

  snapshot() {
    return JSON.stringify({
      name: this.nameTarget.value,
      rows: this.rowTargets.map((row) => [this.val(row, "est"), this.val(row, "rate"), this.checked(row)])
    })
  }

  val(row, key) { return row.querySelector(`[data-invoice-editor-target~="${key}"]`).value.trim() }
  checked(row) { return row.querySelector('[data-invoice-editor-target~="bill"]').checked }

  money(n) { return "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }
  hours(n) { return n.toFixed(1) + " h" }
  valid(text) { return /^\d+(\.\d+)?$/.test(text) }

  recalc() {
    let total = 0, hours = 0, billed = 0, invalid = false
    this.rowTargets.forEach((row) => {
      const estText = this.val(row, "est"), rateText = this.val(row, "rate")
      const estOk = this.valid(estText), rateOk = this.valid(rateText)
      this.mark(row, "est", estOk)
      this.mark(row, "rate", rateOk)
      if (!estOk || !rateOk) invalid = true
      const on = this.checked(row)
      const est = estOk ? parseFloat(estText) : 0
      const rate = rateOk ? parseFloat(rateText) : 0
      const amount = on ? est * rate : 0
      row.querySelector('[data-invoice-editor-target~="amount"]').textContent = this.money(amount)
      row.classList.toggle("row-muted", !on)
      if (on) { total += amount; hours += est; billed++ }
    })

    this.totalTargets.forEach((t) => { t.textContent = this.money(total) })
    this.totalHoursTargets.forEach((t) => { t.textContent = this.hours(hours) })
    this.billedCountTargets.forEach((t) => { t.textContent = `${billed} of ${this.rowTargets.length} tasks billed` })
    this.statEstTargets.forEach((t) => { t.textContent = this.hours(hours) })
    this.statTotalTargets.forEach((t) => { t.textContent = this.money(total) })
    this.errorAlertTarget.hidden = !invalid

    const dirty = this.snapshot() !== this.initial
    this.saveTarget.disabled = !dirty || invalid
    this.badgeTargets.forEach((b) => {
      b.dataset.tone = dirty ? "warning" : "success"
      b.textContent = dirty ? "Unsaved changes" : "Saved"
    })
  }

  mark(row, key, ok) {
    const input = row.querySelector(`[data-invoice-editor-target~="${key}"]`)
    input.setAttribute("aria-invalid", String(!ok))
    input.closest(".input").setAttribute("aria-invalid", String(!ok))
    const error = input.closest("td").querySelector(".field-error")
    if (error) error.hidden = ok
  }
}
