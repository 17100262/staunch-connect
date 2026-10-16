import { Controller } from "@hotwired/stimulus"

// Live password rules and confirmation check; Update stays disabled until everything passes.
export default class extends Controller {
  static targets = ["field", "newPassword", "confirm", "confirmBox", "mismatch", "rule", "submit"]

  static checks = {
    length: (v) => v.length >= 12,
    number: (v) => /\d/.test(v),
    symbol: (v) => /[^A-Za-z0-9\s]/.test(v)
  }

  check() {
    const value = this.newPasswordTarget.value
    let allMet = true
    this.ruleTargets.forEach((rule) => {
      const met = this.constructor.checks[rule.dataset.rule](value)
      rule.querySelector("[data-met]").hidden = !met
      rule.querySelector("[data-unmet]").hidden = met
      if (!met) allMet = false
    })

    const confirm = this.confirmTarget.value
    const mismatch = confirm.length > 0 && confirm !== value
    this.mismatchTarget.hidden = !mismatch
    this.confirmBoxTarget.setAttribute("aria-invalid", String(mismatch))
    const filled = this.fieldTargets.every((f) => f.value.length > 0)
    this.submitTarget.disabled = !(allMet && !mismatch && confirm.length > 0 && filled)
  }

  reveal(event) {
    event.preventDefault()
    const type = this.fieldTargets[0].type === "password" ? "text" : "password"
    this.fieldTargets.forEach((f) => { f.type = type })
  }
}
