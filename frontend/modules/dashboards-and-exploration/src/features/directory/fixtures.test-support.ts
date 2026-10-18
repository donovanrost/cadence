import type { DashboardRow, DirectoryPage } from "./contracts";

export const row = (id: string, overrides: Partial<DashboardRow> = {}): DashboardRow => ({
  id,
  name: `Dashboard ${id}`,
  description: null,
  tags: [],
  archived: false,
  starred: false,
  version: 1,
  updated_at: "2026-10-08T10:00:00Z",
  updated_by: "Dana Rost",
  viewed_at: null,
  ...overrides,
});

export const directoryFixture = (): DirectoryPage => {
  const pass = row("dashboard-1", {
    name: "Pass Overview",
    description: "Live state during a ground station contact",
    tags: ["pass", "comms"],
    starred: true,
    viewed_at: "2026-10-08T11:40:00Z",
  });
  const power = row("dashboard-2", { name: "Power Bus", tags: ["eps"], updated_by: null });
  return {
    sequence: 0,
    model: {
      version: 2,
      mission_id: "mission-1",
      author: true,
      filters: { query: "", tags: [], starred: false, archived: false, sort: "updated", page: 1 },
      available_tags: ["comms", "eps", "pass"],
      total: 2,
      pages: 1,
      page_size: 50,
      rows: [pass, power],
      shortcuts: { starred: [pass], recent: [pass] },
    },
  };
};
