import type { Page } from "@playwright/test";
import { missionApi } from "./console.ts";

/**
 * Limit-alarm fixtures (contract: docs/apogee/api/ops.md `/alarms`). The dev seed configures no
 * limits, so specs that need an alarm route this endpoint. Filters (`spacecraft_id`, `q`,
 * `severity`, `point_id`, `exclude_spacecraft_id`) are applied like the server does, so B1 and B4
 * each see their own slice. `plane` is not (the fixtures carry no planes): B4 still joins the rows
 * to the fleet and keeps the plane's own, so the sister rows are right either way.
 */
export interface AlarmSpec {
  readonly scid: number;
  readonly point: { readonly id: string; readonly name: string; readonly subsystem: string };
  readonly severity: "critical" | "caution";
  readonly firstCrossedAt: string;
  readonly receivedAt: string;
}

const spacecraftId = (scid: number) => `spacecraft-earendil-${String(scid).padStart(3, "0")}`;

function row(spec: AlarmSpec) {
  return {
    id: `limit_event_qa_${spec.scid}_${spec.point.id}`,
    spacecraft_id: spacecraftId(spec.scid),
    point: { ...spec.point, unit: "A", description: null },
    severity: spec.severity,
    active: true,
    // #1117 (#451 T3c): a row is a live alarm state; these ground-limit fields are always null.
    condition: null,
    value: null,
    limit_set_name: null,
    thresholds: null,
    first_crossed_at: spec.firstCrossedAt,
    generation_time: spec.receivedAt,
    received_at: spec.receivedAt,
  };
}

export async function routeAlarms(page: Page, specs: readonly AlarmSpec[]): Promise<void> {
  const all = specs.map(row);
  await page.route(`${missionApi("alarms")}**`, async (route) => {
    const query = new URL(route.request().url()).searchParams;
    const sc = query.get("spacecraft_id");
    const q = query.get("q")?.toLowerCase() ?? null;
    const severity = query.get("severity");
    const pointId = query.get("point_id");
    const excluded = query.get("exclude_spacecraft_id");
    const matching = all.filter(
      (a) =>
        (sc === null || a.spacecraft_id === sc) &&
        (pointId === null || a.point.id === pointId) &&
        (excluded === null || a.spacecraft_id !== excluded) &&
        (severity === null || a.severity === severity) &&
        (q === null ||
          a.point.id.toLowerCase().includes(q) ||
          a.point.name.toLowerCase().includes(q)),
    );
    const alarms = matching.slice(0, Number(query.get("limit") ?? 100));
    const latest =
      all
        .map((a) => a.first_crossed_at)
        .sort()
        .at(-1) ?? null;
    await route.fulfill({
      json: {
        data: {
          observed_at: new Date().toISOString(),
          summary: {
            active: all.length,
            critical: all.filter((a) => a.severity === "critical").length,
            caution: all.filter((a) => a.severity === "caution").length,
            latest_transition_at: latest,
          },
          total: matching.length,
          alarms,
        },
        meta: { next_cursor: null },
      },
    });
  });
}
