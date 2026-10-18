import { expect, test } from "vite-plus/test";
import {
  capturePage,
  createPageActionPort,
  readPageEnvelope,
  validPageToken,
  type PageContext,
} from "./page-admission";

const token = "11111111-1111-4111-8111-111111111111";
const scopes = [
  { slot: "organization.page", context: { organizationId: "org" }, keys: ["organizationId"] },
  {
    slot: "mission.page",
    context: { organizationId: "org", missionId: "mission" },
    keys: ["organizationId", "missionId"],
  },
  {
    slot: "ops.page",
    context: { organizationId: "org", missionId: "mission", resourceId: "resource" },
    keys: ["organizationId", "missionId"],
  },
  {
    slot: "spacecraft.page",
    context: { organizationId: "org", missionId: "mission", spacecraftId: "spacecraft" },
    keys: ["organizationId", "missionId", "spacecraftId"],
  },
] as const;
test.each(scopes)(
  "$slot rejects foreign scope and retires captured capabilities",
  async ({ slot, context, keys }) => {
    const registration = { id: "feature.page", slot, version: 1, actions: ["save"] };
    const snapshot = { ...registration, status: "ready", context, token, data: { value: 1 } };
    const input: {
      contributionId: string;
      snapshot: unknown;
      context: PageContext;
      refreshing: boolean;
    } = {
      contributionId: registration.id,
      snapshot,
      context,
      refreshing: false,
    };
    let alive = true;
    const captured = capturePage(input, registration, keys, () => alive);
    expect(captured.current()).toBe(true);
    for (const [key, value] of Object.entries(context)) {
      expect(() =>
        readPageEnvelope(
          { ...snapshot, context: { ...context, [key]: `${value}-foreign` } },
          registration,
          context,
          keys,
        ),
      ).toThrow();
    }
    if (!("resourceId" in context))
      expect(() =>
        readPageEnvelope(
          { ...snapshot, context: { ...context, resourceId: "foreign" } },
          registration,
          context,
          keys,
        ),
      ).toThrow();
    input.snapshot = { ...snapshot, data: { value: 2 } };
    expect(captured.current()).toBe(true);
    input.refreshing = true;
    expect(captured.active()).toBe(true);
    expect(captured.current()).toBe(false);
    input.refreshing = false;
    const port = createPageActionPort(
      registration,
      token,
      captured.current,
      {
        execute: async () => {
          alive = false;
          return { saved: true };
        },
        navigate: () => {},
      },
      slot,
    );
    await expect(port.execute("undeclared", {})).rejects.toThrow("Inactive");
    await expect(port.execute("save", {})).rejects.toThrow("response");
    expect(captured.active()).toBe(false);
    alive = true;
    input.contributionId = "another.page";
    expect(captured.active()).toBe(false);
  },
);
test("all action scopes require UUID-shaped tokens", () => {
  expect(validPageToken(token)).toBe(true);
  for (const candidate of ["-".repeat(36), "a".repeat(36), token + "\n", null, 1])
    expect(validPageToken(candidate)).toBe(false);
});
