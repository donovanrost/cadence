import type { DirectoryState } from "./contracts";
export const directoryFixture = (): DirectoryState => ({
  sequence: 0,
  phase: "editing",
  model: {
    version: 1,
    mission_id: "mission-1",
    author: true,
    filters: { query: "", lifecycle: "all", tag: "all", sort: "name", page: 1 },
    available_tags: ["flight"],
    total: 2,
    pages: 1,
    page_size: 50,
    rows: [
      {
        id: "dashboard-1",
        name: "Flight telemetry",
        description: "Thermal monitoring",
        tags: ["flight"],
        lifecycle: "active",
        starred: true,
        version: 3,
        published_version: 1,
        widget_count: 4,
      },
      {
        id: "dashboard-2",
        name: "Retired overview",
        description: null,
        tags: [],
        lifecycle: "archived",
        starred: false,
        version: 2,
        published_version: 1,
        widget_count: 1,
      },
    ],
  },
});
