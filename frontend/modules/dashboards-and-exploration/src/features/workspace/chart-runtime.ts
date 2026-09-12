import { inject, onBeforeUnmount, onMounted, type InjectionKey } from "vue";

/** A workspace-instance transport. Its owner must authorize and scope every operation. */
export type ChartAction = "open_data_link" | "open_evidence" | "set_chart_time_range";
export type ChartTopic = "append" | "selection";
export interface ChartRuntimePort {
  readonly version: 1;
  execute(action: ChartAction, payload: Record<string, unknown>): void | Promise<void>;
  subscribe(topic: ChartTopic, listener: (payload: Record<string, unknown>) => void): () => void;
}
export const CHART_RUNTIME_PORT: InjectionKey<ChartRuntimePort> = Symbol(
  "cadence.dashboard.chart-runtime.v1",
);
const actions: readonly string[] = ["open_data_link", "open_evidence", "set_chart_time_range"];
const topics: readonly string[] = ["append", "selection"];
const record = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === "object" && !Array.isArray(value);

/** No transport means a static chart: no global fallback or implicit authority. */
export function useChartRuntime() {
  const port = inject(CHART_RUNTIME_PORT, null);
  let active = false;
  const subscriptions: Array<() => void> = [];
  const listeners: Array<{
    topic: ChartTopic;
    listener: (payload: Record<string, unknown>) => void;
  }> = [];
  onMounted(() => {
    active = true;
    if (port?.version !== 1) return;
    for (const { topic, listener } of listeners) {
      const unsubscribe = port.subscribe(topic, (payload) => {
        if (active && record(payload)) listener(payload);
      });
      if (typeof unsubscribe === "function") subscriptions.push(unsubscribe);
    }
  });
  onBeforeUnmount(() => {
    active = false;
    for (const unsubscribe of subscriptions.splice(0)) unsubscribe();
  });
  return {
    on(topic: ChartTopic, listener: (payload: Record<string, unknown>) => void) {
      if (topics.includes(topic)) listeners.push({ topic, listener });
    },
    pushEvent(action: ChartAction, payload: Record<string, unknown>) {
      if (!active || port?.version !== 1 || !actions.includes(action) || !record(payload)) return;
      // No retries: receipt/error presentation belongs to the owning workspace.
      try {
        void Promise.resolve(port.execute(action, payload)).catch(() => {});
      } catch {
        /* owner failure */
      }
    },
  };
}
