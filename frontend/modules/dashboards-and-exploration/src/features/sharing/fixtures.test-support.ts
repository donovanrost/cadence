import { snapshotFixture } from "../workspace/snapshot-fixture.test-support";
import type { SharedView, SharedViewKind } from "./contracts";
export function sharedViewFixture(kind: SharedViewKind = "snapshot"): SharedView {
  const canvas = snapshotFixture();
  canvas.author = false;
  canvas.document_mode = kind === "share" ? "published" : "snapshot";
  return {
    version: 1,
    organization_id: "org",
    mission_id: "mission",
    id: kind + "-1",
    kind,
    dashboard_id: "dashboard",
    data_visibility: "authorized_runtime_data",
    data_semantics:
      kind === "share" ? "published_definition_current_data" : "definition_at_version_current_data",
    created_at: "2026-09-07T00:00:00Z",
    expires_at: null,
    loaded_at: "2026-09-07T00:01:00Z",
    runtime_context: {},
    definition: {
      name: canvas.name,
      description: "",
      version: 1,
      placements: 1,
      sections: canvas.sections.length,
      json: JSON.stringify({
        organization_id: "org",
        mission_id: "mission",
        dashboard_id: "dashboard",
        name: canvas.name,
        metadata: { version: 1 },
        grid: canvas.grid,
        placements: canvas.placements.map((p) => ({
          placement_id: p.authored_id,
          section_id: p.section_id,
          layout: p.layout,
        })),
        sections: canvas.sections.map((s) => ({ section_id: s.id, title: s.title })),
      }),
    },
    canvas,
  };
}
export const sharedViewContext = (kind: SharedViewKind = "snapshot") => ({
  organizationId: "org",
  missionId: "mission",
  resourceId: kind + "-1",
});
