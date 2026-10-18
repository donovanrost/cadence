import type { CreationPage } from "./contracts";
export function creationFixture(): CreationPage {
  return {
    creation: {
      version: 1,
      context: { organizationId: "org_one", missionId: "mission_one" },
      actor_id: "user_one",
      mission_name: "Flight mission",
      stage_id: "stage_new",
    },
    write_token: "c".repeat(64),
    operation: null,
  };
}
