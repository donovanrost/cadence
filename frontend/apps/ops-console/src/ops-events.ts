import { inject, onBeforeUnmount, onMounted, type InjectionKey } from "vue";
import type { HostBridge } from "@cadence/plugin-sdk";

export const OPS_EVENT_BRIDGE: InjectionKey<HostBridge> = Symbol("cadence.ops.event-bridge");

export type OpsEventPayload =
  | Record<string, unknown>
  | unknown[]
  | string
  | number
  | boolean
  | null;
type OpsEventCallback = (payload: OpsEventPayload) => void;

export function useOpsEvent(eventName: string, callback: OpsEventCallback): void {
  const listener = (event: Event): void => {
    callback((event as CustomEvent<OpsEventPayload>).detail);
  };

  onMounted(() => {
    window.addEventListener(eventName, listener);
  });

  onBeforeUnmount(() => {
    window.removeEventListener(eventName, listener);
  });
}

export function useOpsVue(): { pushEvent: (eventName: string, payload: OpsEventPayload) => void } {
  const bridge = inject(OPS_EVENT_BRIDGE, null);

  return {
    pushEvent(eventName, payload) {
      window.dispatchEvent(
        new CustomEvent("cadence:ops-event", {
          detail: { eventName, payload, bridge },
        }),
      );
    },
  };
}

export function emitOpsEvent(eventName: string, payload: OpsEventPayload): void {
  window.dispatchEvent(new CustomEvent(eventName, { detail: payload }));
}
