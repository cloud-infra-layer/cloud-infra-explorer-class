import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tooltip", "point"]

  show(event) {
    const point = event.currentTarget
    const tooltip = this.tooltipTarget
    tooltip.hidden = false
    tooltip.textContent = point.dataset.label

    const figureRect = this.element.getBoundingClientRect()
    const pointRect = point.getBoundingClientRect()
    const tooltipRect = tooltip.getBoundingClientRect()

    let left = pointRect.left - figureRect.left + pointRect.width / 2 - tooltipRect.width / 2
    let top = pointRect.top - figureRect.top - tooltipRect.height - 10

    left = Math.max(8, Math.min(left, figureRect.width - tooltipRect.width - 8))
    if (top < 8) top = pointRect.bottom - figureRect.top + 10

    tooltip.style.left = `${left}px`
    tooltip.style.top = `${top}px`
  }

  hide() {
    this.tooltipTarget.hidden = true
  }
}
