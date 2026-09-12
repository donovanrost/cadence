import type { SpacecraftCommandingModel } from "./contracts";
export const context = {
  organizationId: "org-a",
  missionId: "mission-a",
  spacecraftId: "spacecraft-a",
};
export function spacecraftCommandingFixture(): SpacecraftCommandingModel {
  return {
    version: 1,
    context,
    mission_name: "Firebird",
    spacecraft_name: "FB-1",
    scid: 0,
    profile: {
      status: "ready",
      id: "profile-a",
      version: 2,
      name: "Pinned bus",
      lifecycle: "active",
      uplink: "tc",
      packet: "space_packet",
    },
    query: { page: 1, query: "" },
    endpoints: {
      page: 1,
      total_count: 1,
      items: [{ id: "spacecraft_runtime:spacecraft-a", name: "FB-1 runtime", scid: 0 }],
    },
  };
}
