type VueInstance = {
  vue?: { app: { unmount(): void } | null };
  liveSocket?: { isUnloaded(): boolean };
};
type VueHook = { destroyed(this: VueInstance): void; reconnected?(this: VueInstance): void };

/** Teleported pages must disappear with their transport, including history patches. */
export function withImmediateVueUnmount<T extends VueHook>(hook: T): T {
  return {
    ...hook,
    reconnected(this: VueInstance) {
      hook.reconnected?.call(this);
      window.dispatchEvent(new Event("cadence:transport-reconnected"));
    },
    destroyed(this: VueInstance) {
      // Phoenix unloads its views inside the native submit event, before the
      // browser serializes the form. Keep that DOM alive for document navigation.
      // LiveVue's deferred cleanup remains responsible for this path.
      if (!this.liveSocket?.isUnloaded() && this.vue?.app) {
        const app = this.vue.app;
        this.vue.app = null;
        app.unmount();
      }
      // Always preserve LiveVue's injector and registry cleanup.
      hook.destroyed.call(this);
    },
  };
}
