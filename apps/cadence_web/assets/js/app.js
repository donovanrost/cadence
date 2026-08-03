import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {createLiveToastHook} from "../../../../deps/live_toast"
import ClipboardButton from "./hooks/clipboard_button"
import CsvDownload from "./hooks/csv_download"
import DashboardGrid from "./hooks/dashboard_grid"
import DashboardEditorGuard from "./hooks/dashboard_editor_guard"
import DropdownMenu from "./hooks/dropdown_menu"
import NavRail from "./hooks/nav_rail"
import Overlay from "./hooks/overlay"
import ResizablePanel from "./hooks/resizable_panel"
import TelemetryChart from "./hooks/telemetry_chart"
import TimeRangeRecents from "./hooks/time_range_recents"
import UtcClock from "./hooks/utc_clock"

const Hooks = {
  ClipboardButton,
  CsvDownload,
  DashboardGrid,
  DashboardEditorGuard,
  DropdownMenu,
  LiveToast: createLiveToastHook(),
  NavRail,
  Overlay,
  ResizablePanel,
  TelemetryChart,
  TimeRangeRecents,
  UtcClock
}

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
  dom: {
    // GridStack adds client-only state morphdom would otherwise strip:
    // the generated gs-id-* class scopes the generated row stylesheet (losing
    // it collapses the grid), and during edit mode the client is layout-
    // authoritative for item gs-* attrs until autosave round-trips.
    onBeforeElUpdated(from, to) {
      // <details> open state is client-side UI state. Dashboard sections may
      // render open by default, so preserve both the opened and closed state;
      // popovers only need their transient opened state preserved.
      if (from.tagName === "DETAILS" && from.hasAttribute("data-dashboard-section")) {
        if (from.hasAttribute("open")) to.setAttribute("open", "")
        else to.removeAttribute("open")
      } else if (from.tagName === "DETAILS" && from.hasAttribute("open")) {
        to.setAttribute("open", "")
      }

      if (from.classList.contains("grid-stack")) {
        to.className = from.className
        const style = from.getAttribute("style")
        if (style) to.setAttribute("style", style)
        const row = from.getAttribute("gs-current-row")
        if (row) to.setAttribute("gs-current-row", row)
      }

      if (from.classList.contains("grid-stack-item")) {
        // GridStack injects resize-handle child <div>s the server template
        // knows nothing about. Preserve them on every patch — not just in
        // edit mode: the patch that exits edit mode flips the container's
        // data-edit-mode to "false" before items are walked, and stripping
        // the handles there makes GridStack's own teardown (setStatic ->
        // removeChild) crash mid-cleanup, leaving drag dead for the next
        // edit session. GridStack removes them itself when it tears down.
        from
          .querySelectorAll(":scope > .ui-resizable-handle")
          .forEach((handle) => to.appendChild(handle.cloneNode(true)))

        if (from.closest("[data-edit-mode='true']")) {
          // During edit mode the client is layout-authoritative for item
          // gs-* attrs until autosave round-trips, and the ui-* classes
          // carry GridStack drag/resize state morphdom would drop.
          for (const attr of ["gs-x", "gs-y", "gs-w", "gs-h"]) {
            const value = from.getAttribute(attr)
            if (value != null) to.setAttribute(attr, value)
          }

          to.className = from.className
        }
      }

      return true
    }
  }
})

liveSocket.connect()

window.liveSocket = liveSocket
