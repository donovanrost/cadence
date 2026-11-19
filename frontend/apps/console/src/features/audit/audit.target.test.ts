import { describe, expect, it } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import { targetRoute } from "./api.ts";

const organization = {
  slug: "reflect-orbital",
  missions: [{ id: missionId("mission_1"), slug: "earendil", name: "Earendil" }],
};
const event = (kind: string, id: string | null, mission: string | null = "mission_1") => ({
  target: { kind, id, label: "SET_MODE and 2 more for 12 spacecraft" },
  mission: mission === null ? null : { id: mission, name: "Earendil" },
});

describe("audit targets that open a page (api 11-15)", () => {
  it("opens a command group's page in its mission; its :requestId is the group id", () => {
    expect(targetRoute(event("command_group", "group_7"), organization)).toEqual({
      name: "ops.commands.request",
      params: { org: "reflect-orbital", mission: "earendil", requestId: "group_7" },
    });
  });
  it("leaves single requests, unknown kinds and unplaceable rows as text", () => {
    expect(targetRoute(event("command_request", "req_1"), organization)).toBeNull();
    expect(targetRoute(event("launch_window", "x"), organization)).toBeNull();
    expect(targetRoute(event("command_group", null), organization)).toBeNull();
    expect(targetRoute(event("command_group", "group_7", null), organization)).toBeNull();
    expect(
      targetRoute(event("command_group", "group_7", "mission_other"), organization),
    ).toBeNull();
    expect(targetRoute(event("command_group", "group_7"), null)).toBeNull();
    expect(targetRoute({ target: null, mission: null }, organization)).toBeNull();
  });
});
