import type { Directory } from "./contracts";
export function directoryFixture(): Directory {
  return {
    version: 1,
    context: { organizationId: "org_one", missionId: "mission_one" },
    actor_id: "user_one",
    mission_name: "Flight mission",
    observed_at: "2026-09-10T12:00:00Z",
    query: { after: "", state: "", query: "" },
    stages: {
      limit: 25,
      entries: [
        {
          id: "stage_one",
          name: "Flight preparation",
          state: "draft",
          visibility: "private",
          owner_id: "user_one",
        },
      ],
      next_after: null,
    },
  };
}
