/**
 * ExecutionChannel Hook
 *
 * Connects to the Phoenix ExecutionChannel for real-time procedure execution updates.
 * Receives state immediately on join (catch-up) and forwards all events to LiveView.
 *
 * Usage:
 *   <div id="execution-channel"
 *        phx-hook="ExecutionChannel"
 *        data-execution-id="<%= @execution.id %>"
 *        data-socket-token="<%= @socket_token %>">
 *   </div>
 */

import { Socket } from "phoenix"

export const ExecutionChannelHook = {
  mounted() {
    this.executionId = this.el.dataset.executionId
    this.socketToken = this.el.dataset.socketToken

    if (!this.executionId || !this.socketToken) {
      console.error("[ExecutionChannel] Missing execution ID or socket token")
      return
    }

    console.log(`[ExecutionChannel] Connecting to execution:${this.executionId}`)

    // Create socket connection
    this.socket = new Socket("/socket", {
      params: { token: this.socketToken }
    })

    this.socket.connect()

    // Join the execution channel
    this.channel = this.socket.channel(`execution:${this.executionId}`, {})

    // Handle initial state (catch-up)
    this.channel.on("state", (state) => {
      console.log("[ExecutionChannel] Received initial state:", state)
      this.pushEvent("execution_state", state)
    })

    // Handle step events
    this.channel.on("step_started", (payload) => {
      console.log("[ExecutionChannel] Step started:", payload.step)
      this.pushEvent("channel_step_started", payload)
    })

    this.channel.on("step_completed", (payload) => {
      console.log("[ExecutionChannel] Step completed:", payload.step)
      this.pushEvent("channel_step_completed", payload)
    })

    this.channel.on("step_failed", (payload) => {
      console.log("[ExecutionChannel] Step failed:", payload.step)
      this.pushEvent("channel_step_failed", payload)
    })

    this.channel.on("step_blocked", (payload) => {
      console.log("[ExecutionChannel] Step blocked:", payload.step)
      this.pushEvent("channel_step_blocked", payload)
    })

    this.channel.on("step_skipped", (payload) => {
      console.log("[ExecutionChannel] Step skipped:", payload.step)
      this.pushEvent("channel_step_skipped", payload)
    })

    // Handle status changes
    this.channel.on("status_changed", (payload) => {
      console.log("[ExecutionChannel] Status changed:", payload.status)
      this.pushEvent("channel_status_changed", payload)
    })

    // Handle log messages
    this.channel.on("log", (payload) => {
      this.pushEvent("channel_log", payload)
    })

    // Join the channel
    this.channel.join()
      .receive("ok", () => {
        console.log(`[ExecutionChannel] Joined execution:${this.executionId}`)
      })
      .receive("error", (resp) => {
        console.error("[ExecutionChannel] Failed to join:", resp)
      })
  },

  destroyed() {
    if (this.channel) {
      this.channel.leave()
    }
    if (this.socket) {
      this.socket.disconnect()
    }
  }
}

export default ExecutionChannelHook
