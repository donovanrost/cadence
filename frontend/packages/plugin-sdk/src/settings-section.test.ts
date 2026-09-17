import { describe, expect, it } from "vite-plus/test";
import { readSettingsSectionDefinition, SETTINGS_SECTION_SLOT } from "./settings-section";

const section = () => ({
  id: "commanding.defaults",
  slot: SETTINGS_SECTION_SLOT,
  version: 1,
  scopes: ["organization", "mission"],
  title: "Commanding",
  description: "Command workspace defaults.",
  owner: { kind: "application", applicationKey: "commanding", label: "Commanding" },
});
describe("settings discovery metadata", () => {
  it("copies and freezes metadata without promoting renderer data into authority", () => {
    const input = {
      ...section(),
      permissions: ["manage_settings"],
      route: "/admin",
      component: "unadmitted",
    };
    const accepted = readSettingsSectionDefinition(input);
    input.scopes.pop();
    expect(accepted.scopes).toEqual(["organization", "mission"]);
    expect(accepted).not.toHaveProperty("permissions");
    expect(accepted).not.toHaveProperty("route");
    expect(accepted).not.toHaveProperty("component");
    expect(Object.isFrozen(accepted)).toBe(true);
    expect(Object.isFrozen(accepted.owner)).toBe(true);
    expect(Object.isFrozen(accepted.scopes)).toBe(true);
  });
  it.each([
    { version: 2 },
    { slot: "ops.page" },
    { scopes: [] },
    { scopes: ["spacecraft"] },
    { scopes: ["mission", "mission"] },
    { id: "../settings" },
    { title: " " },
    { description: "x".repeat(401) },
    { owner: { kind: "application", label: "Commands" } },
    { owner: { kind: "admin", label: "Cadence" } },
  ])("rejects unsupported metadata %j", (invalid) => {
    expect(() => readSettingsSectionDefinition({ ...section(), ...invalid })).toThrow();
  });
  it("supports a host section with no application installation identity", () => {
    expect(
      readSettingsSectionDefinition({ ...section(), owner: { kind: "host", label: "Cadence" } })
        .owner,
    ).toEqual({ kind: "host", label: "Cadence" });
  });
});
