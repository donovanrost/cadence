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
    (m: any) => (m.version = 2),
    (m: any) => (m.revision = Number.MAX_SAFE_INTEGER + 1),
    (m: any) => (m.published_version = 3),
    (m: any) => (m.tags = ["duplicate", "duplicate"]),
    (m: any) => (m.tags = [" untrimmed "]),
    (m: any) => (m.defaults_json = JSON.stringify({ value: "x".repeat(4097) })),
    (m: any) => (m.query.dashboard_id = "forged"),
    (m: any) => (m.shares.rows[0].runtime_context = { secret: "hidden" }),
    (m: any) => (m.shares.rows[0].state = "expired"),
    (m: any) => (m.shares.rows[0].data_visibility = "public"),
    (m: any) => (m.snapshots.rows[0].document = {}),
    (m: any) => (m.snapshots.rows[0].document_version = 3),
    (m: any) => (m.deployments.rows[0].digest_prefix = "not-a-digest"),
    (m: any) => (m.deployments.rows[0].environment = "x".repeat(121)),
    (m: any) => (m.loaded_at = "yesterday"),
  ]) {
    const model = fixture();
    mutate(model);
    expect(() => readSettingsModel(model, context)).toThrow();
  }
});
test("pagination is bounded, unique and tied to the last returned record", () => {
  const model = fixture();
  model.shares.rows = Array.from({ length: 25 }, (_, i) => ({
    ...model.shares.rows[0],
    id: `share-${i}`,
  }));
  model.shares.next = "share-24";
  expect(readSettingsModel(model, context)).toEqual(model);
  model.shares.next = "forged";
  expect(() => readSettingsModel(model, context)).toThrow();
  model.shares.next = null;
  model.shares.rows.push({ ...model.shares.rows[0], id: "overflow" });
  expect(() => readSettingsModel(model, context)).toThrow();
  model.shares.rows.pop();
  model.shares.rows[1].id = model.shares.rows[0].id;
  expect(() => readSettingsModel(model, context)).toThrow();
});
