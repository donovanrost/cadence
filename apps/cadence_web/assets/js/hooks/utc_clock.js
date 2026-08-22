// Client-side UTC clock for the ops status bar — no server ticks involved.
const UtcClock = {
  mounted() {
    this.render()
    this.timer = setInterval(() => this.render(), 1000)
  },

  destroyed() {
    clearInterval(this.timer)
  },

  render() {
    const now = new Date()
    const pad = (n) => String(n).padStart(2, "0")
    this.el.textContent =
      `${pad(now.getUTCHours())}:${pad(now.getUTCMinutes())}:${pad(now.getUTCSeconds())} UTC`
  },
}

export default UtcClock
