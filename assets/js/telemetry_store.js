/**
 * TelemetryStore - Client-side telemetry data buffer and subscription manager.
 *
 * This store:
 * - Maintains a circular buffer of recent values for each telemetry item
 * - Provides a pub/sub interface for widgets to subscribe to updates
 * - Manages the connection to the TelemetryChannel
 *
 * Usage:
 *   const store = new TelemetryStore({ maxSamples: 1000 })
 *   await store.connect(token, missionId)
 *
 *   // Subscribe to updates
 *   const unsub = store.subscribe("SAT-1:HEALTH:CPU_TEMP", (value, timestamp) => {
 *     console.log("New value:", value)
 *   })
 *
 *   // Get historical data for charts
 *   const history = store.getHistory("SAT-1:HEALTH:CPU_TEMP", 100)
 */

import { connect as connectSocket, joinTelemetryChannel } from "./user_socket"

function normalizeKeyParts(key) {
  if (!key) return { normalizedKey: key, target: null, packet: null, item: null, qualifiedItem: null }

  const [target, packet, ...rest] = key.split(":")
  const item = rest.join(":")

  if (!target || !packet || !item) {
    return { normalizedKey: key, target, packet, item, qualifiedItem: item }
  }

  const prefix = `${packet}.`
  const normalizedItem = item.startsWith(prefix) ? item.slice(prefix.length) : item
  const qualifiedItem = item.includes(".") ? item : `${packet}.${item}`

  return {
    normalizedKey: `${target}:${packet}:${normalizedItem}`,
    target,
    packet,
    item: normalizedItem,
    qualifiedItem
  }
}

/**
 * Simple circular buffer for storing telemetry history.
 */
class CircularBuffer {
  constructor(capacity) {
    this.capacity = capacity
    this.buffer = []
    this.head = 0
    this.size = 0
  }

  push(item) {
    if (this.size < this.capacity) {
      this.buffer.push(item)
      this.size++
    } else {
      this.buffer[this.head] = item
    }
    this.head = (this.head + 1) % this.capacity
  }

  toArray() {
    if (this.size < this.capacity) {
      return [...this.buffer]
    }
    // Return in chronological order
    return [
      ...this.buffer.slice(this.head),
      ...this.buffer.slice(0, this.head)
    ]
  }

  get length() {
    return this.size
  }

  last() {
    if (this.size === 0) return undefined
    const idx = (this.head - 1 + this.capacity) % this.capacity
    return this.buffer[idx]
  }

  clear() {
    this.buffer = []
    this.head = 0
    this.size = 0
  }
}

/**
 * TelemetryStore class for managing real-time telemetry data.
 */
export class TelemetryStore {
  constructor(options = {}) {
    this.maxSamples = options.maxSamples || 1000
    this.data = new Map()         // key -> CircularBuffer
    this.subscribers = new Map()  // key -> Set of callbacks
    this.channel = null
    this.missionId = null
    this.connected = false
    this.pendingSubscriptions = new Set()  // Keys waiting to be subscribed on server
    this.connectionListeners = new Set()   // Callbacks for connection state changes
  }

  /**
   * Connect to the telemetry channel for a mission.
   *
   * @param {string} token - Authentication token
   * @param {string} missionId - Mission ID to subscribe to
   * @param {Array} initialSubscriptions - Initial items to subscribe to
   * @returns {Promise} Resolves when connected and joined
   */
  async connect(token, missionId, initialSubscriptions = []) {
    this.missionId = missionId

    // Connect to socket
    connectSocket(token)

    // Join telemetry channel
    this.channel = joinTelemetryChannel(missionId, initialSubscriptions)

    return new Promise((resolve, reject) => {
      this.channel
        .join()
        .receive("ok", () => {
          this._setConnected(true)
          this._setupChannelHandlers()
          console.log(`[TelemetryStore] Joined telemetry channel for mission ${missionId}`)
          resolve()
        })
        .receive("error", (resp) => {
          console.error("[TelemetryStore] Failed to join channel:", resp)
          this._setConnected(false)
          reject(new Error(`Failed to join telemetry channel: ${JSON.stringify(resp)}`))
        })
        .receive("timeout", () => {
          console.error("[TelemetryStore] Channel join timeout")
          this._setConnected(false)
          reject(new Error("Channel join timeout"))
        })

      // Handle channel errors and closes
      this.channel.onError(() => {
        console.error("[TelemetryStore] Channel error")
        this._setConnected(false)
      })

      this.channel.onClose(() => {
        console.log("[TelemetryStore] Channel closed")
        this._setConnected(false)
      })
    })
  }

  /**
   * Disconnect from the telemetry channel.
   */
  disconnect() {
    if (this.channel) {
      this.channel.leave()
      this.channel = null
    }
    this._setConnected(false)
    this.missionId = null
  }

  /**
   * Subscribe to connection state changes.
   *
   * @param {Function} callback - Called with (connected: boolean) on state change
   * @returns {Function} Unsubscribe function
   */
  onConnectionChange(callback) {
    this.connectionListeners.add(callback)
    // Immediately notify of current state
    callback(this.connected)
    return () => this.connectionListeners.delete(callback)
  }

  /**
   * Check if currently connected.
   *
   * @returns {boolean}
   */
  isConnected() {
    return this.connected
  }

  // Update connected state and notify listeners
  _setConnected(connected) {
    if (this.connected !== connected) {
      this.connected = connected
      for (const listener of this.connectionListeners) {
        try {
          listener(connected)
        } catch (err) {
          console.error("[TelemetryStore] Connection listener error:", err)
        }
      }
    }
  }

  /**
   * Subscribe to updates for a telemetry item.
   *
   * @param {string} key - Telemetry key in format "target:packet:item"
   * @param {Function} callback - Called with (value, timestamp, limitsState) on updates
   * @returns {Function} Unsubscribe function
   */
  subscribe(key, callback) {
    const { normalizedKey } = normalizeKeyParts(key)

    if (!this.subscribers.has(normalizedKey)) {
      this.subscribers.set(normalizedKey, new Set())
      // Request server subscription
      this._serverSubscribe([normalizedKey])
    }

    this.subscribers.get(normalizedKey).add(callback)

    // Return unsubscribe function
    return () => {
      const subs = this.subscribers.get(normalizedKey)
      if (subs) {
        subs.delete(callback)
        if (subs.size === 0) {
          this.subscribers.delete(normalizedKey)
          // Unsubscribe from server to stop receiving updates
          this._serverUnsubscribe([normalizedKey])
        }
      }
    }
  }

  /**
   * Subscribe to multiple items at once.
   *
   * @param {Array<string>} keys - Array of telemetry keys
   * @param {Function} callback - Called with (key, value, timestamp, limitsState) on updates
   * @returns {Function} Unsubscribe function
   */
  subscribeMany(keys, callback) {
    const newKeys = []

    for (const key of keys) {
      const { normalizedKey } = normalizeKeyParts(key)

      if (!this.subscribers.has(normalizedKey)) {
        this.subscribers.set(normalizedKey, new Set())
        newKeys.push(normalizedKey)
      }
      this.subscribers.get(normalizedKey).add((value, timestamp, limitsState) => {
        callback(normalizedKey, value, timestamp, limitsState)
      })
    }

    // Batch subscribe new keys
    if (newKeys.length > 0) {
      this._serverSubscribe(newKeys)
    }

    // Return unsubscribe function that removes all subscriptions
    return () => {
      const keysToUnsubscribe = []
      for (const key of keys) {
        const { normalizedKey } = normalizeKeyParts(key)
        const subs = this.subscribers.get(normalizedKey)
        if (subs) {
          // Note: This removes ALL subscribers for this key, not just the one callback
          // For fine-grained control, use individual subscribe() calls
          this.subscribers.delete(normalizedKey)
          keysToUnsubscribe.push(normalizedKey)
        }
      }
      if (keysToUnsubscribe.length > 0) {
        this._serverUnsubscribe(keysToUnsubscribe)
      }
    }
  }

  /**
   * Get historical values for a telemetry item.
   *
   * @param {string} key - Telemetry key
   * @param {number} count - Maximum number of values to return
   * @returns {Array<{value: any, timestamp: number, limitsState: string}>}
   */
  getHistory(key, count = 100) {
    const { normalizedKey } = normalizeKeyParts(key)
    const buffer = this.data.get(normalizedKey)
    if (!buffer) return []

    const arr = buffer.toArray()
    return arr.slice(-count)
  }

  /**
   * Get the most recent value for a telemetry item.
   *
   * @param {string} key - Telemetry key
   * @returns {{value: any, timestamp: number, limitsState: string}|undefined}
   */
  getCurrent(key) {
    const { normalizedKey } = normalizeKeyParts(key)
    const buffer = this.data.get(normalizedKey)
    return buffer?.last()
  }

  /**
   * Check if we have any data for a key.
   *
   * @param {string} key - Telemetry key
   * @returns {boolean}
   */
  has(key) {
    const { normalizedKey } = normalizeKeyParts(key)
    return this.data.has(normalizedKey) && this.data.get(normalizedKey).length > 0
  }

  /**
   * Clear all stored data (but keep subscriptions).
   */
  clear() {
    for (const buffer of this.data.values()) {
      buffer.clear()
    }
  }

  /**
   * Request current values from server for all subscribed items.
   *
   * @returns {Promise}
   */
  async refreshCurrentValues() {
    if (!this.channel || !this.connected) {
      throw new Error("Not connected to telemetry channel")
    }

    return new Promise((resolve, reject) => {
      this.channel
        .push("get_current", {})
        .receive("ok", (response) => {
          this._handleCurrentValues(response.values)
          resolve(response.values)
        })
        .receive("error", reject)
        .receive("timeout", () => reject(new Error("Timeout")))
    })
  }

  // Private methods

  _setupChannelHandlers() {
    // Handle real-time telemetry updates
    this.channel.on("telemetry_update", (payload) => {
      this._handleTelemetryUpdate(payload)
    })

    // Handle initial/current values response
    this.channel.on("current_values", (payload) => {
      this._handleCurrentValues(payload.values)
    })
  }

  _handleTelemetryUpdate(payload) {
    const { items, timestamp } = payload

    for (const item of items) {
      this._updateItem(item)
    }
  }

  _handleCurrentValues(values) {
    for (const item of values) {
      this._updateItem(item)
    }
  }

  _updateItem(item) {
    const { key, value, limits_state, received_time } = item
    const { normalizedKey } = normalizeKeyParts(key)

    // Ensure buffer exists
    if (!this.data.has(normalizedKey)) {
      this.data.set(normalizedKey, new CircularBuffer(this.maxSamples))
    }

    const entry = {
      value,
      timestamp: received_time,
      limitsState: limits_state
    }

    // Add to buffer
    this.data.get(normalizedKey).push(entry)

    // Notify subscribers
    const subs = this.subscribers.get(normalizedKey)
    if (subs) {
      for (const callback of subs) {
        try {
          callback(value, received_time, limits_state)
        } catch (err) {
          console.error(`[TelemetryStore] Subscriber error for ${key}:`, err)
        }
      }
    }
  }

  _serverSubscribe(keys) {
    if (!this.channel || !this.connected) {
      // Queue for later
      for (const key of keys) {
        this.pendingSubscriptions.add(key)
      }
      return
    }

    const items = keys.map(key => {
      const { target, packet, qualifiedItem } = normalizeKeyParts(key)
      return { target, packet, item: qualifiedItem }
    })

    this.channel
      .push("subscribe", { items })
      .receive("ok", (resp) => {
        console.log(`[TelemetryStore] Subscribed to ${resp.count} items`)
      })
      .receive("error", (err) => {
        console.error("[TelemetryStore] Subscribe error:", err)
      })
  }

  _serverUnsubscribe(keys) {
    if (!this.channel || !this.connected) return

    const items = keys.map(key => {
      const { target, packet, qualifiedItem } = normalizeKeyParts(key)
      return { target, packet, item: qualifiedItem }
    })

    this.channel
      .push("unsubscribe", { items })
      .receive("ok", (resp) => {
        console.log(`[TelemetryStore] Unsubscribed, ${resp.count} remaining`)
      })
      .receive("error", (err) => {
        console.error("[TelemetryStore] Unsubscribe error:", err)
      })
  }
}

// Create singleton instance
let defaultStore = null

/**
 * Get or create the default TelemetryStore instance.
 *
 * @param {Object} options - Options for creating the store
 * @returns {TelemetryStore}
 */
export function getStore(options = {}) {
  if (!defaultStore) {
    defaultStore = new TelemetryStore(options)
  }
  return defaultStore
}

/**
 * Reset the default store (useful for testing or reconnection).
 */
export function resetStore() {
  if (defaultStore) {
    defaultStore.disconnect()
    defaultStore = null
  }
}

export default {
  TelemetryStore,
  getStore,
  resetStore
}
