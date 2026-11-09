import type { Page } from "@playwright/test";
import { missionApi } from "./console.ts";

/**
 * Limit-alarm fixtures (contract: docs/apogee/api/ops.md `/alarms`). The dev seed configures no
 * limits, so specs that need an alarm route this endpoint. Filters (`spacecraft_id`, `q`,
 * `severity`) are applied like the server does, so B1 and B4 each see their own slice.
 */
export interface AlarmSpec {
  readonly scid: number;
  readonly point: { readonly id: string; readonly name: string; readonly subsystem: string };
  readonly severity: "critical" | "caution";
  readonly condition: "red_low" | "red_high" | "yellow_low" | "yellow_high";
  readonly value: number;
  readonly thresholds: Readonly<
    Record<"red_low" | "yellow_low" | "yellow_high" | "red_high", number | null>
  >;
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
    condition: spec.condition,
    value: spec.value,
    limit_set_name: "DEFAULT",
    thresholds: spec.thresholds,
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
    const alarms = all.filter(
      (a) =>
        (sc === null || a.spacecraft_id === sc) &&
        (severity === null || a.severity === severity) &&
        (q === null ||
          a.point.id.toLowerCase().includes(q) ||
          a.point.name.toLowerCase().includes(q)),
    );
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
          alarms,
        },
      },
    });
  });
}
