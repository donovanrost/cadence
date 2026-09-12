import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, waitFor, within, userEvent } from "storybook/test";
import { provide, ref } from "vue";
import {
  CHART_RUNTIME_PORT,
  type ChartRuntimePort,
  type ChartTopic,
} from "@cadence/dashboards-and-exploration/charts";
import { TelemetryChart } from "@cadence/dashboards-and-exploration/charts";

const start = Date.UTC(2026, 8, 5, 18, 40);
const args = {
  chart_id: "story-telemetry-chart",
  widget_id: "story-temperature",
  placement_id: "story-placement",
  window_seconds: 300,
  correlation_group: "story-chart",
  label: "Battery temperature",
  unit: "°C",
  time_mode: "historical",
  time_from: new Date(start).toISOString(),
  time_to: new Date(start + 300_000).toISOString(),
  backfill: Array.from({ length: 31 }, (_, index) => [
    start + index * 10_000,
    18 + Math.sin(index / 4) * 2,
  ]),
};

const meta = {
  title: "Applications/Ops Console/Telemetry Chart",
  component: TelemetryChart,
  parameters: { layout: "padded" },
  args,
  render: (args) => ({
    components: { TelemetryChart },
    setup: () => ({ args }),
    template:
      '<section aria-label="Battery temperature history" class="h-80 card p-4"><TelemetryChart v-bind="args" /></section>',
  }),
} satisfies Meta<typeof args>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Production: Story = {
  play: async ({ canvasElement }) => {
    await waitFor(() => expect(canvasElement.querySelector("canvas")).not.toBeNull());
    const overlay = canvasElement.querySelector<HTMLElement>(".u-over");
    if (!overlay) throw Error("Missing chart overlay");
    await expect(getComputedStyle(overlay).position).toBe("absolute");
    await expect(overlay.getBoundingClientRect().width).toBeGreaterThan(0);
    const firstCanvas = canvasElement.querySelector("canvas");
    const root = document.documentElement;
    const previous = root.style.getPropertyValue("--chart-color-label");
    try {
      root.style.setProperty("--chart-color-label", "220, 210, 190");
      await waitFor(() => expect(canvasElement.querySelector("canvas")).not.toBe(firstCanvas));
      await expect(canvasElement.querySelectorAll("canvas").length).toBeGreaterThan(0);
    } finally {
      if (previous) root.style.setProperty("--chart-color-label", previous);
      else root.style.removeProperty("--chart-color-label");
    }
  },
};

export const LiveAndSelection: Story = {
  render: () => ({
    components: { TelemetryChart },
    setup() {
      const now = Date.now();
      const shown = ref(true);
      const subscriptions = ref(0);
      const listeners = new Map<ChartTopic, Set<(payload: Record<string, unknown>) => void>>();
      const port: ChartRuntimePort = {
        version: 1,
        execute() {},
        subscribe(topic, listener) {
          const bucket = listeners.get(topic) ?? new Set();
          bucket.add(listener);
          listeners.set(topic, bucket);
          subscriptions.value += 1;
          return () => {
            bucket.delete(listener);
            subscriptions.value -= 1;
          };
        },
      };
      provide(CHART_RUNTIME_PORT, port);
      const publish = (topic: ChartTopic, payload: Record<string, unknown>) => {
        for (const listener of listeners.get(topic) ?? []) listener(payload);
      };
      const liveArgs = {
        ...args,
        time_mode: "live",
        window_seconds: 60,
        correlation_group: "story-live",
        backfill: [
          [now - 80_000, 10],
          [now - 30_000, 12, { link_id: "point", sample_id: "sample" }],
          [now, 13],
        ],
      };
      const append = () =>
        publish("append", {
          series: { "story-temperature": [[now + 10_000, 14]] },
          markers: {
            "story-temperature": {
              event_markers: [
                {
                  marker_id: "watermark",
                  marker_type: "source_watermark_cursor",
                  timestamp_ms: now - 5_000,
                  freshness_state: "stale",
                  data_source_id: "source",
                  display_mode: "cursor",
                },
              ],
            },
          },
          window_end_ms: now + 10_000,
          refresh_interval_ms: 1_000,
        });
      const select = () =>
        publish("selection", {
          selection: {
            placement_id: args.placement_id,
            target: "telemetry_sample",
            target_id: "sample",
            link_id: "point",
            timestamp_ms: now - 30_000,
          },
        });
      return { liveArgs, shown, subscriptions, append, select };
    },
    template: `<div>
      <button @click="append">Append samples</button>
      <button @click="select">Select evidence</button>
      <button @click="shown = false">Unmount charts</button>
      <output data-chart-subscriptions>{{ subscriptions }}</output>
      <div v-if="shown" class="grid gap-4">
        <section class="h-64 card p-4"><TelemetryChart v-bind="liveArgs" chart_id="story-live-main" /></section>
        <section class="h-64 card p-4"><TelemetryChart v-bind="liveArgs" chart_id="story-live-peer" widget_id="peer" placement_id="peer" /></section>
      </div>
    </div>`,
  }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const chart = (id: string) => {
      const element = canvasElement.querySelector<HTMLElement>(`#${id}`);
      if (!element) throw Error(`Missing chart ${id}`);
      return element;
    };
    await waitFor(() => expect(chart("story-live-main").querySelector("canvas")).not.toBeNull());
    await userEvent.click(canvas.getByRole("button", { name: "Append samples" }));
    await waitFor(() => expect(chart("story-live-main").dataset.chartPointCount).toBe("3"));
    await expect(chart("story-live-peer").dataset.chartPointCount).toBe("2");
    await userEvent.click(canvas.getByRole("button", { name: "Select evidence" }));
    await waitFor(() =>
      expect(
        chart("story-live-main").querySelector('[data-chart-selection-target="telemetry sample"]'),
      ).not.toBeNull(),
    );
    await expect(
      chart("story-live-peer").querySelector('[data-chart-selection-target="telemetry sample"]'),
    ).toBeNull();
    const control = chart("story-live-main").querySelector<HTMLElement>(
      '[data-event-marker-target="source watermark"]',
    );
    const overlay = chart("story-live-main").querySelector<HTMLElement>(".u-over");
    if (!control || !overlay) throw Error("Missing watermark cursor control");
    const bounds = overlay.getBoundingClientRect();
    control.dispatchEvent(
      new MouseEvent("mousemove", {
        clientX: bounds.left + bounds.width / 2,
        clientY: bounds.top + bounds.height / 2,
        bubbles: true,
      }),
    );
    await waitFor(async () => {
      const tooltip = chart("story-live-peer").querySelector<HTMLElement>(
        "[data-chart-shared-tooltip]",
      );
      if (!tooltip) throw Error("Missing peer tooltip");
      await expect(tooltip.style.display).toBe("block");
    });
    await userEvent.click(canvas.getByRole("button", { name: "Unmount charts" }));
    await waitFor(() => expect(canvasElement.querySelectorAll("canvas")).toHaveLength(0));
    await expect(canvasElement.querySelector("[data-chart-subscriptions]")?.textContent).toBe("0");
  },
};
