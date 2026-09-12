import { widgetDefaults, type EditorState } from "./contracts";
export const editorContext = {
  organizationId: "org-1",
  missionId: "mission-1",
  resourceId: "dashboard-1",
};
export function editorFixture(): EditorState {
  return {
    version: 2,
    revision: 0,
    dirty: false,
    sequence: 0,
    phase: "editing",
    model: {
      version: 3,
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      document_version: 1,
      name: "Flight overview",
      description: "Operator workspace",
      defaults: { ...widgetDefaults },
      runtime_defaults_json: JSON.stringify({
        time: { mode: "live", refresh_ms: 1000 },
        data: { realm: "flight" },
        overlays: { quality: true },
      }),
      grid: { columns: 12, row_height_px: 64, gap_px: 8 },
      sections: [{ id: "power", title: "Power", description: "", collapsed_by_default: false }],
      placements: [
        {
          id: "battery",
          section_id: "power",
          title: "Battery voltage",
          editable: true,
          fields: { ...widgetDefaults, title: "Battery voltage", section_id: "power" },
          observables: ["tlm.hk.battery_voltage"],
          layout: { x: 0, y: 0, w: 4, h: 2 },
          constraints: { min_w: 2, min_h: 2, max_w: 12, max_h: 24, max_y: 23 },
        },
      ],
      preview: null,
    },
  };
}
