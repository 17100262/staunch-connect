import { Controller } from "@hotwired/stimulus"

// List filters kept in hidden inputs and submitted as a GET form: toggle chips,
// a single-choice menu and a multi-choice menu. Every change reloads the list.
export default class extends Controller {
  static targets = ["ai", "range", "attendees", "page"]

  toggleAi() {
    this.aiTarget.value = this.aiTarget.value === "1" ? "" : "1"
    this.submit()
  }

  setRange(event) {
    this.rangeTarget.value = event.params.value
    this.submit()
  }

  togglePerson(event) {
    event.preventDefault()
    const value = event.params.value
    const existing = this.attendeesTargets.find((input) => input.value === value)
    if (existing) existing.remove()
    else {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "attendees[]"
      input.value = value
      input.dataset.filtersTarget = "attendees"
      this.element.appendChild(input)
    }
    this.submit()
  }

  clearPeople(event) {
    event.preventDefault()
    this.attendeesTargets.forEach((input) => input.remove())
    this.submit()
  }

  submit() {
    if (this.hasPageTarget) this.pageTarget.value = ""
    this.element.requestSubmit()
  }
}
