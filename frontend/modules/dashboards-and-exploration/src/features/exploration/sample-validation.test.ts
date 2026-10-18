import { expect, test } from "vite-plus/test";
import { context, fixture, selectedFixture } from "./fixtures.test-support";
import { readExploration } from "./validation";

test("physical inspection requires the selected identity and rejects unselected data", () => {
  const model = selectedFixture();
  expect(readExploration(model, context)).toBe(model);
  expect(
    readExploration(
      {
        ...model,
        query: {
          ...model.query,
          selected_data_source_id: "source-a",
          selected_source_binding_id: "binding-a",
        },
      },
      context,
    ),
  ).toBeTruthy();
  for (const pins of [
    { selected_data_source_id: "foreign", selected_source_binding_id: "binding-a" },
    { selected_data_source_id: "source-a", selected_source_binding_id: "foreign" },
    { selected_data_source_id: "source-a" },
    { selected_source_binding_id: "binding-a" },
  ])
    expect(() =>
      readExploration({ ...model, query: { ...model.query, ...pins } }, context),
    ).toThrow();
  expect(() => readExploration({ ...model, query: fixture().query }, context)).toThrow();
  expect(() => readExploration({ ...model, inspection: fixture().inspection }, context)).toThrow();
  for (const query of [
    { sample_id: "foreign" },
    { point_id: "foreign" },
    { data_source_id: "foreign" },
    { source_binding_id: "foreign" },
    { realm: "simulation" },
    { spacecraft_id: "foreign" },
    { scope_kind: "source_endpoint", scope_id: "foreign" },
    { scope_kind: "spacecraft", scope_id: "foreign" },
    { replay_run_id: "foreign" },
  ])
    expect(() =>
      readExploration({ ...model, query: { ...model.query, ...query } }, context),
    ).toThrow();
});

test("selection timestamps compare at microsecond precision and validate calendar dates", () => {
  const model = selectedFixture();
  for (const selected_time of ["2026-09-07T11:59:59.654321Z", "2026-09-07T13:59:59.654321+02:00"])
    expect(
      readExploration({ ...model, query: { ...model.query, selected_time } }, context),
    ).toBeTruthy();
  for (const selected_time of [
    "2026-09-07T11:59:59.654320Z",
    "2026-02-30T11:59:59.654321Z",
    "2026-09-07T24:00:00Z",
  ])
    expect(() =>
      readExploration({ ...model, query: { ...model.query, selected_time } }, context),
    ).toThrow();
});

test("inspection rejects extra fields, invalid clocks, unsafe references and unbounded values", () => {
  const model = selectedFixture();
  if (model.inspection.status !== "ready") throw Error("fixture must be ready");
  const sample = model.inspection.sample;
  for (const bad of [
    { ...sample, credentials: "secret" },
    { ...sample, receipt_time: "2026-02-30T12:00:00Z" },
    { ...sample, source: { ...sample.source, credentials: "secret" } },
    { ...sample, record: { ...sample.record, packet_definition_version: 9007199254740992 } },
    { ...sample, record: { ...sample.record, packet_id: "a".repeat(257) } },
    { ...sample, raw_value: { state: "ready", text: "1".repeat(4097), format: "json" } },
    { ...sample, raw_value: { state: "ready", text: "{", format: "json" } },
    { ...sample, raw_value: { state: "ready", text: "xyz", format: "hex" } },
    { ...sample, raw_value: { state: "limited", text: "partial", format: null } },
  ])
    expect(() =>
      readExploration({ ...model, inspection: { status: "ready", sample: bad } }, context),
    ).toThrow();
  for (const state of ["not_recorded", "limited", "unsupported"])
    expect(
      readExploration(
        {
          ...model,
          inspection: {
            status: "ready",
            sample: {
              ...sample,
              raw_value: { state, text: null, format: null },
            },
          },
        },
        context,
      ),
    ).toBeTruthy();
});
