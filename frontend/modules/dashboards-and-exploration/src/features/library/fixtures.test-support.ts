import type { LibraryState } from "./contracts";
import { widgetExample } from "./widget-json";
export const libraryContext = { organizationId: "org-1", missionId: "mission-1" };
export function libraryFixture(selected = true): LibraryState {
  const item = {
    id: "library-1",
    name: "Power tile",
    description: "Reusable power telemetry",
    latest_version: 2,
  };
  const target = { id: "dashboard-1", name: "Flight systems", version: 3 };
  return {
    sequence: 0,
    phase: "ready",
    model: {
      version: 1,
      organization_id: "org-1",
      mission_id: "mission-1",
      query: {
        q: "",
        after: null,
        item_id: selected ? item.id : null,
        version: selected ? 1 : null,
        before_version: null,
        consumer_after: null,
        dashboard_query: "",
        dashboard_after: null,
        target_id: selected ? target.id : null,
      },
      items: [item],
      next_item: null,
      selected: selected
        ? {
            item,
            version: 1,
            widget_json: widgetExample,
            versions: [2, 1].map((version) => ({
              version,
              summary: `Saved version ${version}`,
              actor_id: "user-1",
              saved_at: "2026-09-07T12:00:00Z",
            })),
            next_version: null,
            consumers: {
              total: 1,
              next: null,
              rows: [{ ...target, pins: [{ id: "pin-1", version: 1 }] }],
            },
          }
        : null,
      dashboards: [target, { id: "dashboard-2", name: "Thermal", version: 1 }],
      next_dashboard: null,
      target: selected ? target : null,
    },
  };
}
