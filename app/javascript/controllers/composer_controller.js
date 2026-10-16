import { Controller } from "@hotwired/stimulus"

// Chat composer. Auto-grows (max 160px); Enter sends, Shift+Enter adds a line.
// On send it shows the question and typing dots straight away, before the answer
// arrives. After ~8 seconds it says so and offers Cancel.
export default class extends Controller {
  static targets = ["field", "send"]

  grow() {
    const field = this.fieldTarget
    field.style.height = "auto"
    field.style.height = `${Math.min(field.scrollHeight, 160)}px`
    if (this.hasSendTarget && !this.sendTarget.dataset.locked) this.sendTarget.disabled = field.value.trim() === ""
  }

  key(event) {
    if (event.target !== this.fieldTarget || event.key !== "Enter" || event.shiftKey || event.isComposing) return
    event.preventDefault()
    if (this.fieldTarget.value.trim()) this.element.requestSubmit()
  }

  submitted(event) {
    const question = this.fieldTarget.value.trim()
    if (!question) return

    this.question = question
    this.submission = event.detail.formSubmission
    const thread = document.getElementById("messages")
    if (!thread) return

    document.getElementById("empty_hint")?.setAttribute("hidden", "")
    thread.hidden = false

    const bottom = document.getElementById("chat_bottom")
    this.userNode = this.node(`<div class="msg-user pre-wrap" data-optimistic></div>`)
    this.userNode.textContent = question
    this.replyNode = this.node(`<div class="msg-ai" data-optimistic><span class="avatar" data-size="sm"><svg class="icon" aria-hidden="true"><use href="#i-sparkles"/></svg></span><div class="msg-body"><div class="typing" role="status" aria-label="Staunch Connect is typing"><i></i><i></i><i></i></div></div></div>`)
    thread.insertBefore(this.userNode, bottom)
    thread.insertBefore(this.replyNode, bottom)
    bottom?.scrollIntoView({ block: "end" })

    this.fieldTarget.value = ""
    this.grow()
    this.timer = setTimeout(() => this.slow(), 8000)
  }

  finished() {
    clearTimeout(this.timer)
  }

  slow() {
    const body = this.replyNode?.querySelector(".msg-body")
    if (!body) return
    body.insertAdjacentHTML("beforeend", `<p>Still looking. This is taking longer than usual.</p><div class="msg-actions"><button type="button" class="btn btn-ghost" data-size="sm">Cancel</button></div>`)
    body.querySelector("button").addEventListener("click", () => this.cancel())
  }

  cancel() {
    clearTimeout(this.timer)
    this.submission?.stop()
    this.userNode?.remove()
    this.replyNode?.remove()
    this.fieldTarget.value = this.question || ""
    this.grow()
    this.fieldTarget.focus()
  }

  node(html) {
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    return template.content.firstElementChild
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
