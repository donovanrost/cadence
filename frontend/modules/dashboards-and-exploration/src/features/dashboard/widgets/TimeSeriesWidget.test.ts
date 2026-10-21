import { expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import TelemetryChart from "../../workspace/TelemetryChart.vue";
import { snapshotFixture } from "../../workspace/snapshot-fixture.test-support";
import TimeSeriesWidget from "./TimeSeriesWidget.vue";

test("live dashboard refreshes replace chart snapshots without waiting for an append stream", async () => {
  const snapshot = snapshotFixture("time_series");
  const placement = snapshot.placements[0];
  if (!placement) throw Error("Missing chart fixture");
  const app = mount(TimeSeriesWidget, {
    props: {
      placement,
      context: { ...snapshot.context, time_mode: "live" },
      live: true,
      group: "demo",
      chartId: "demo-chart",
    },
    global: { stubs: { TelemetryChart: true } },
  });
  try {
    const chart = app.getComponent(TelemetryChart);
    expect(chart.props("time_mode")).toBe("snapshot");
    const previous: unknown = chart.props("backfill");
    const next = structuredClone(placement);
    const value = next.frames[0]?.fields.find((field) => field.name === "voltage");
    if (!value) throw Error("Missing voltage fixture");
    value.values = [29.1, 29.2, 29.3];
    await app.setProps({ placement: next });
    expect(chart.props("backfill")).not.toEqual(previous);
    await app.setProps({ live: false });
    expect(chart.props("time_mode")).toBe("snapshot");
    await app.setProps({ context: snapshot.context });
    expect(chart.props("time_mode")).toBe("range");
  } finally {
    app.unmount();
  }
});
