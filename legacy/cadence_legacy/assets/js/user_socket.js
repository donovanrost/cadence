/**
 * Phoenix UserSocket for telemetry channel connections.
 *
 * This module handles the WebSocket connection to the server
 * and provides a simple API for joining telemetry channels.
 */

import { Socket } from "phoenix"

let socket = null

/**
 * Initialize the socket connection with an authentication token.
 *
 * @param {string} token - The authentication token from the server
 * @returns {Socket} The connected socket instance
 */
export function connect(token) {
  if (socket && socket.isConnected()) {
    return socket
  }

  socket = new Socket("/socket", {
    params: { token },
    logger: (kind, msg, data) => {
      if (process.env.NODE_ENV === "development") {
        console.log(`[Socket ${kind}]`, msg, data)
      }
    }
  })

  socket.connect()

  socket.onError(() => {
    console.error("[Socket] Connection error")
  })

  socket.onClose(() => {
    console.log("[Socket] Connection closed")
  })

  return socket
}

/**
 * Get the current socket instance.
 *
 * @returns {Socket|null} The socket instance or null if not connected
 */
export function getSocket() {
  return socket
}

/**
 * Disconnect the socket.
 */
export function disconnect() {
  if (socket) {
    socket.disconnect()
    socket = null
  }
}

/**
 * Join a telemetry channel for a specific mission.
 *
 * @param {string} missionId - The mission ID to subscribe to
 * @param {Array} subscriptions - Initial telemetry subscriptions
 * @returns {Channel} The joined channel instance
 */
export function joinTelemetryChannel(missionId, subscriptions = []) {
  if (!socket) {
    throw new Error("Socket not connected. Call connect() first.")
  }

  const channel = socket.channel(`telemetry:${missionId}`, {
    subscriptions: subscriptions.map(s => ({
      target: s.target,
      packet: s.packet,
      item: s.item
    }))
  })

  return channel
}

export default {
  connect,
  getSocket,
  disconnect,
  joinTelemetryChannel
}
