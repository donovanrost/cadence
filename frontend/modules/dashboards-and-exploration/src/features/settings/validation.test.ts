import { fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { expect, test } from "vite-plus/test";
import { readSettingsModel } from "./validation";
import { settingsModel as fixture, settingsContext as context } from "./fixtures.test-support";
test("admits bounded semantic settings without interpreting the legacy presentation contract", () => {
  const model = fixture();
  expect(readSettingsModel(model, context)).toEqual(model);
  expect(readSettingsModel({ ...model, lifecycle: "archived" }, context).lifecycle).toBe(
    "archived",
  );
  expect(() => readSettingsModel(model, { ...context, organizationId: "foreign" })).toThrow();
  expect(() => readSettingsModel(model, { ...context, missionId: "foreign" })).toThrow();
  expect(() => readSettingsModel(model, { ...context, resourceId: "foreign" })).toThrow();
});
test("rejects forged identity, unsupported versions, raw payloads and unbounded metadata", () => {
  for (const mutate of [
    (m: unknown) => (fixtureRecordAt(m).version = 2),
    (m: unknown) => (fixtureRecordAt(m).revision = Number.MAX_SAFE_INTEGER + 1),
    (m: unknown) => (fixtureRecordAt(m).published_version = 3),
    (m: unknown) => (fixtureRecordAt(m).tags = ["duplicate", "duplicate"]),
    (m: unknown) => (fixtureRecordAt(m).tags = [" untrimmed "]),
    (m: unknown) =>
      (fixtureRecordAt(m).defaults_json = JSON.stringify({ value: "x".repeat(4097) })),
    (m: unknown) => (fixtureRecordAt(m, "query").dashboard_id = "forged"),
    (m: unknown) =>
      (fixtureRecordAt(m, "shares", "rows", 0).runtime_context = { secret: "hidden" }),
    (m: unknown) => (fixtureRecordAt(m, "shares", "rows", 0).state = "expired"),
    (m: unknown) => (fixtureRecordAt(m, "shares", "rows", 0).data_visibility = "public"),
    (m: unknown) => (fixtureRecordAt(m, "snapshots", "rows", 0).document = {}),
    (m: unknown) => (fixtureRecordAt(m, "snapshots", "rows", 0).document_version = 3),
    (m: unknown) => (fixtureRecordAt(m, "deployments", "rows", 0).digest_prefix = "not-a-digest"),
    (m: unknown) => (fixtureRecordAt(m, "deployments", "rows", 0).environment = "x".repeat(121)),
    (m: unknown) => (fixtureRecordAt(m).loaded_at = "yesterday"),
  ]) {
    const model = fixture();
    mutate(model);
    expect(() => readSettingsModel(model, context)).toThrow();
  }
});
test("pagination is bounded, unique and tied to the last returned record", () => {
  const model = fixture();
  model.shares.rows = Array.from({ length: 25 }, (_, i) => ({
    ...required(model.shares.rows[0]),
    id: `share-${i}`,
  }));
  model.shares.next = "share-24";
  expect(readSettingsModel(model, context)).toEqual(model);
  model.shares.next = "forged";
  expect(() => readSettingsModel(model, context)).toThrow();
  model.shares.next = null;
  model.shares.rows.push({ ...required(model.shares.rows[0]), id: "overflow" });
  expect(() => readSettingsModel(model, context)).toThrow();
  model.shares.rows.pop();
  required(model.shares.rows[1]).id = required(model.shares.rows[0]).id;
  expect(() => readSettingsModel(model, context)).toThrow();
});
