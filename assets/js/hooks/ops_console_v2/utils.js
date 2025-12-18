/**
 * Utility methods for Ops Console V2 Hook
 */

/**
 * Debounce utility methods
 */
export const utilsMethods = {
  _debounce(key, fn, delay) {
    if (!this._debounceTimers) {
      this._debounceTimers = {}
    }

    if (this._debounceTimers[key]) {
      clearTimeout(this._debounceTimers[key])
    }

    this._debounceTimers[key] = setTimeout(fn, delay)
  }
}
