import { required } from "../../../../../test-support/required";
import { expect, test } from "vite-plus/test";
import {
  diagnosticContext,
  diagnosticFixture,
  diagnosticWarningFixture,
} from "./fixtures.test-support";
import { readExecutionDiagnostics } from "./validation";

test("admits read-time inspection separately from recorded decision evidence", () => {
  const m = diagnosticFixture();
  expect(readExecutionDiagnostics(m, diagnosticContext)).toBe(m);
  m.collections[0] = { id: "plan", state: "unavailable", source: null, limited: false, rows: [] };
  required(m.collections[5]).source = "process_local";
  expect(readExecutionDiagnostics(m, diagnosticContext)).toBe(m);
});
test("warning rows have an exact plan-only schema and semantic severity and scope", () => {
  const m = diagnosticFixture();
  required(m.collections[0]).rows.push(diagnosticWarningFixture());
  expect(readExecutionDiagnostics(m, diagnosticContext)).toBe(m);
  for (const mutate of [
    (row: ReturnType<typeof diagnosticWarningFixture>) => Object.assign(row, { kind: "warning" }),
    (row: ReturnType<typeof diagnosticWarningFixture>) => Object.assign(row, { status: "ready" }),
    (row: ReturnType<typeof diagnosticWarningFixture>) => Object.assign(row, { message: "secret" }),
    (row: ReturnType<typeof diagnosticWarningFixture>) =>
      Object.assign(required(row.details[0]), { value: null }),
    (row: ReturnType<typeof diagnosticWarningFixture>) =>
      Object.assign(required(row.details[1]), { value: "unknown" }),
    (row: ReturnType<typeof diagnosticWarningFixture>) =>
      Object.assign(required(row.details[2]), { value: "" }),
    (row: ReturnType<typeof diagnosticWarningFixture>) =>
      Object.assign(required(row.details[3]), { value: "bad\nidentity" }),
    (row: ReturnType<typeof diagnosticWarningFixture>) =>
      Object.assign(required(row.details[5]), { value: 1 }),
    (row: ReturnType<typeof diagnosticWarningFixture>) => row.details.reverse(),
    (row: ReturnType<typeof diagnosticWarningFixture>) =>
      row.details.push({ key: "evidence", value: "secret" }),
  ]) {
    const model = structuredClone(m);
    mutate(required(required(model.collections[0]).rows[1]));
    expect(() => readExecutionDiagnostics(model, diagnosticContext)).toThrow();
  }
  required(m.collections[1]).rows.push(required(required(m.collections[0]).rows.pop()));
  expect(() => readExecutionDiagnostics(m, diagnosticContext)).toThrow();
});
test("rejects foreign identity, version changes and undeclared producer fields", () => {
  for (const patch of [
    { organization_id: "foreign" },
    { mission_id: "foreign" },
    { dashboard_id: "foreign" },
    { version: 1 },
    { version: 3 },
    { document_version: null },
    { document_version: 1.5 },
    { loaded_at: "yesterday" },
    { renderer: "arbitrary-component" },
    { name: "x".repeat(4097) },
  ])
    expect(() =>
      readExecutionDiagnostics({ ...diagnosticFixture(), ...patch }, diagnosticContext),
    ).toThrow();
});
test("rejects missing, reordered and over-limit collections and duplicate row identities", () => {
  for (const mutate of [
    (m: ReturnType<typeof diagnosticFixture>) => m.collections.pop(),
    (m: ReturnType<typeof diagnosticFixture>) => m.collections.reverse(),
    (m: ReturnType<typeof diagnosticFixture>) =>
      required(m.collections[0]).rows.push(required(required(m.collections[0]).rows[0])),
    (m: ReturnType<typeof diagnosticFixture>) =>
      (required(m.collections[0]).rows = Array.from({ length: 51 }, () =>
        required(required(m.collections[0]).rows[0]),
      )),
    (m: ReturnType<typeof diagnosticFixture>) =>
      (required(required(m.collections[0]).rows[0]).identity = "x".repeat(257)),
  ]) {
    const m = diagnosticFixture();
    mutate(m);
    expect(() => readExecutionDiagnostics(m, diagnosticContext)).toThrow();
  }
});
test("unavailable is not an empty successful read and source provenance cannot be substituted", () => {
  for (const patch of [
    { state: "unavailable" },
    { source: "durable" },
    { limited: "yes" },
    { source: null },
  ]) {
    const m = diagnosticFixture();
    Object.assign(required(m.collections[0]), patch);
    expect(() => readExecutionDiagnostics(m, diagnosticContext)).toThrow();
  }
});
test("rejects raw payloads, private metadata, non-scalar details and renamed detail keys", () => {
  for (const patch of [
    { payload: { secret: "no" } },
    { details: [] },
    { details: [{ key: "authorization", value: "no" }] },
    { identity: "bad\u0000identity" },
    { id: "not-a-diagnostic-id" },
  ]) {
    const m = diagnosticFixture();
    Object.assign(required(required(m.collections[0]).rows[0]), patch);
    expect(() => readExecutionDiagnostics(m, diagnosticContext)).toThrow();
  }
  const m = diagnosticFixture();
  Object.assign(required(required(required(m.collections[0]).rows[0]).details[0]), {
    value: { secret: "no" },
  });
  expect(() => readExecutionDiagnostics(m, diagnosticContext)).toThrow();
});
test("counts and booleans retain semantic types instead of accepting arbitrary scalar replacements", () => {
  for (const [index, value] of [
    [1, -1],
    [1, "1"],
    [6, "true"],
    [0, 7],
    [0, true],
  ] as const) {
    const m = diagnosticFixture();
    Object.assign(required(required(required(m.collections[0]).rows[0]).details[index]), { value });
    expect(() => readExecutionDiagnostics(m, diagnosticContext)).toThrow();
  }
});
