import type { Page } from "@playwright/test";
import { missionApi } from "./console.ts";

/**
 * Deterministic telemetry history (contract: docs/apogee/api/ops.md, history). Real samples age out
 * of every relative window, so specs that need a plotted series route this: one bucket a minute
 * over the last hour of the requested window, a slow sine around `centre`.
 */
export async function routeHistory(page: Page, centre = 2): Promise<void> {
  await page.route(`${missionApi("telemetry/points/*/history")}**`, async (route) => {
    const url = new URL(route.request().url());
    const pointId = decodeURIComponent(
      url.pathname.split("/points/")[1]?.split("/history")[0] ?? "",
    );
    const to = new Date(url.searchParams.get("to") ?? Date.now()).getTime();
    const from = new Date(url.searchParams.get("from") ?? to - 3_600_000).getTime();
    const width = 60_000;
    const start = Math.max(from, to - 3_600_000);
    const buckets = [];
    for (let t = start; t + width <= to; t += width) {
      const mean = centre + Math.sin((t - start) / 600_000);
      buckets.push({
        t: new Date(t).toISOString(),
        t_end: new Date(t + width).toISOString(),
        min: mean - 0.2,
        max: mean + 0.2,
        mean,
        count: 60,
      });
    }
    await route.fulfill({
      json: {
        data: {
          point_id: pointId,
          unit: "A",
          description: null,
          spacecraft_id: url.searchParams.get("spacecraft_id"),
          from: new Date(from).toISOString(),
          to: new Date(to).toISOString(),
          bucket_width_ms: width,
          truncated: false,
          buckets,
        },
      },
    });
  });
}
