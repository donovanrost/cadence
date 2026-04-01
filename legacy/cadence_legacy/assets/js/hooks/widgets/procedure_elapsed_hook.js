/**
 * ProcedureElapsed Hook
 *
 * Updates elapsed time display for running procedures.
 * Runs a client-side timer to avoid server round-trips for time updates.
 *
 * Expected data attributes:
 * - data-started-at: ISO8601 timestamp of when procedure started
 * - data-status: Current procedure status (running, paused, completed, etc.)
 */

export const ProcedureElapsedHook = {
  mounted() {
    this.startedAt = this.el.dataset.startedAt
    this.status = this.el.dataset.status
    this.intervalId = null

    this._updateDisplay()

    // Start interval if running
    if (this.status === "running") {
      this._startTimer()
    }
  },

  updated() {
    const newStartedAt = this.el.dataset.startedAt
    const newStatus = this.el.dataset.status

    // Check if status changed
    if (newStatus !== this.status) {
      this.status = newStatus
      this.startedAt = newStartedAt

      if (this.status === "running") {
        this._startTimer()
      } else {
        this._stopTimer()
      }
    }

    this._updateDisplay()
  },

  destroyed() {
    this._stopTimer()
  },

  _startTimer() {
    if (this.intervalId) return

    this.intervalId = setInterval(() => {
      this._updateDisplay()
    }, 1000)
  },

  _stopTimer() {
    if (this.intervalId) {
      clearInterval(this.intervalId)
      this.intervalId = null
    }
  },

  _updateDisplay() {
    if (!this.startedAt) {
      this.el.textContent = "--:--"
      return
    }

    try {
      const startDate = new Date(this.startedAt)
      const now = new Date()
      const elapsed = Math.max(0, Math.floor((now - startDate) / 1000))

      this.el.textContent = this._formatElapsed(elapsed)
    } catch (err) {
      this.el.textContent = "--:--"
    }
  },

  _formatElapsed(seconds) {
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const secs = seconds % 60

    if (hours > 0) {
      return `${hours}:${this._pad(minutes)}:${this._pad(secs)}`
    }
    return `${minutes}:${this._pad(secs)}`
  },

  _pad(num) {
    return num.toString().padStart(2, "0")
  }
}

export default ProcedureElapsedHook
