import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, waitFor } from "storybook/test";
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
    const overlay = canvasElement.querySelector<HTMLElement>(".u-over")!;
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
