import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "feedback", "service"]

  connect() {
    this.reset()
  }

  submit(event) {
    if (this.buttonTarget.disabled) {
      event.preventDefault()
      return
    }

    if (!this.serviceTargets.some(service => service.checked)) {
      event.preventDefault()
      this.feedbackTarget.textContent = "Select at least one service."
      this.serviceTargets[0].focus()
      return
    }

    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = "Scanning…"
    this.feedbackTarget.textContent = "Scan in progress. This may take a moment."
  }

  reset(event) {
    if (event?.type === "change" && this.buttonTarget.disabled) return

    this.buttonTarget.disabled = false
    this.buttonTarget.textContent = "Refresh resources"
    this.feedbackTarget.textContent = ""
  }
}
