// Storage transport for the dashboard time picker's "Recently used absolute
// ranges" list. LiveView owns the rendered list; this hook only syncs the
// browser-local history: it pushes stored ranges up on mount and persists new
// ranges pushed down after an absolute range is applied.
const STORAGE_KEY = "cadence:dashboard-time-recents"
const MAX_RECENTS = 4

function readRecents() {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY))
    if (!Array.isArray(parsed)) return []

    return parsed
      .filter((range) => range && typeof range.from === "string" && typeof range.to === "string")
      .slice(0, MAX_RECENTS)
  } catch {
    return []
  }
}

export default {
  mounted() {
    this.pushRecents(readRecents())

    this.handleEvent("cadence:store-time-recent", ({from, to}) => {
      if (typeof from !== "string" || typeof to !== "string") return

      const deduped = readRecents().filter(
        (range) => range.from !== from || range.to !== to
      )
      const recents = [{from, to}, ...deduped].slice(0, MAX_RECENTS)

      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(recents))
      } catch {
        // Storage may be unavailable (private browsing quota); the pushed
        // list still updates the current LiveView session.
      }

      this.pushRecents(recents)
    })
  },

  pushRecents(ranges) {
    this.pushEvent("time_recents_loaded", {ranges})
  }
}
