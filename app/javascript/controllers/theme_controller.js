import { Controller } from "@hotwired/stimulus"

// Light / dark switch in the account menu. The choice is remembered per browser
// and applied before first paint by a small script in the page head.
export default class extends Controller {
  static targets = ["light", "dark"]

  connect() {
    const current = document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light"
    this.mark(current)
  }

  light() { this.apply("light") }
  dark() { this.apply("dark") }

  apply(theme) {
    document.documentElement.setAttribute("data-theme", theme)
    try { localStorage.setItem("sc.theme", theme) } catch (e) {}
    this.mark(theme)
  }

  mark(theme) {
    this.lightTarget.setAttribute("aria-checked", String(theme === "light"))
    this.darkTarget.setAttribute("aria-checked", String(theme === "dark"))
  }
}
