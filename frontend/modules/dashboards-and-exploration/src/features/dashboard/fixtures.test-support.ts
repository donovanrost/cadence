import { snapshotContext, snapshotFixture } from "../workspace/snapshot-fixture.test-support";
import type { WorkspaceSnapshot } from "../workspace/contracts";
import { widgetDefaults, type DashboardOutline, type DashboardPageData } from "./contracts";

export const pageContext = snapshotContext;

export function viewPage(
  snapshot: WorkspaceSnapshot | null = snapshotFixture(),
): DashboardPageData {
  return {
    version: 2,
    mode: "view",
    sequence: 0,
    author: true,
    publication: {
      latest_version: 2,
      published_version: 1,
      published_at: "2026-10-01T00:00:00Z",
      lifecycle: "active",
      state: "draft_ahead",
    },
    snapshot,
    scope_options: [{ id: "sc-1", name: "Pathfinder" }],
    live: { active: false, refresh_ms: null },
    edit: null,
    resolved_at: "2026-10-08T12:00:00Z",
  };
}

export function outline(): DashboardOutline {
  return {
    version: 3,
    organization_id: "org",
    mission_id: "mission",
    dashboard_id: "dashboard",
    document_version: 2,
    name: "Flight telemetry",
    description: "",
    defaults: { ...widgetDefaults },
    runtime_defaults_json: "{}",
    grid: { columns: 12, row_height_px: 80, gap_px: 8 },
    sections: [{ id: "power", title: "Power", description: "", collapsed_by_default: false }],
    placements: [
      {
        id: "battery",
        section_id: "power",
        title: "Battery",
        editable: true,
        fields: { ...widgetDefaults, title: "Battery", section_id: "power" },
        observables: ["battery_voltage"],
        layout: { x: 0, y: 0, w: 6, h: 3 },
        constraints: { min_w: 1, min_h: 1, max_w: 12, max_h: 24, max_y: 1000 },
      },
    ],
  };
}

export function editPage(sequence = 0, dirty = false): DashboardPageData {
  const snapshot = { ...snapshotFixture(), document_mode: "draft" as const };
  return {
    ...viewPage(snapshot),
    mode: "edit",
    sequence,
    snapshot,
    edit: { revision: sequence, dirty, conflict: false, document_version: 2, outline: outline() },
  };
}

/** The same page for another dashboard identity, e.g. a host journey's route. */
export function forContext(
  page: DashboardPageData,
  context: { organizationId: string; missionId: string; resourceId: string },
): DashboardPageData {
  const ids = {
    organization_id: context.organizationId,
    mission_id: context.missionId,
    dashboard_id: context.resourceId,
  };
  if (page.mode === "edit")
    return {
      ...page,
      snapshot: { ...page.snapshot, ...ids },
      edit: { ...page.edit, outline: { ...page.edit.outline, ...ids } },
    };
  return { ...page, snapshot: page.snapshot ? { ...page.snapshot, ...ids } : null };
}
