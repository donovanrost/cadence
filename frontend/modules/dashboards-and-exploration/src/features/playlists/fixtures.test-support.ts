import type { DirectoryState, Presentation } from "./contracts";
export const playlistContext = { organizationId: "org-1", missionId: "mission-1" };
export function directoryFixture(): DirectoryState {
  return {
    sequence: 0,
    phase: "ready",
    model: {
      version: 1,
      organization_id: "org-1",
      mission_id: "mission-1",
      query: { q: "", after: null },
      playlists: {
        rows: [
          {
            id: "playlist-1",
            name: "Flight rotation",
            description: "Operations",
            count: 2,
            dwell_seconds: 30,
            wallboard_mode: false,
          },
        ],
        next: null,
      },
      choices: {
        rows: [
          { id: "dashboard-1", name: "Power", published_version: 1 },
          { id: "dashboard-2", name: "Thermal", published_version: null },
        ],
        next: null,
      },
    },
  };
}
export function presentationFixture(): Presentation {
  return {
    version: 1,
    organization_id: "org-1",
    mission_id: "mission-1",
    playlist: {
      id: "playlist-1",
      name: "Flight rotation",
      description: "Operations",
      dwell_seconds: 30,
      wallboard_mode: false,
    },
    index: 0,
    total: 2,
    playing: false,
    loaded_at: "2026-09-07T18:00:00Z",
    current: { id: "dashboard-1", name: "Power", snapshot: null },
  };
}
