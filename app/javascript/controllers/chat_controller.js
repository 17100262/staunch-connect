import { Controller } from "@hotwired/stimulus"

// Keeps the chat scrolled to the latest message as Turbo Streams append new ones.
export default class extends Controller {
  static targets = ["messages", "bottom"]

  connect() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.messagesTarget, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollToBottom() {
    this.bottomTarget.scrollIntoView({ block: "end" })
  }
}
