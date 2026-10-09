import { fixtureRecord } from "../../../../../test-support/json-fixture";
import { expect, test } from "vite-plus/test";
import { formatRuntimeDefaults, parseRuntimeDefaults, setRuntimeDefault } from "./runtime-defaults";

test("formatting cannot make an admitted near-limit document uneditable", () => {
  const value = {
    items: Array.from({ length: 8 }, () => "x".repeat(4000)),
    more: Array(100).fill(1),
  };
  expect(JSON.stringify(value).length).toBeLessThan(32768);
  expect(JSON.stringify(value, null, 2).length).toBeGreaterThan(32768);
  expect(parseRuntimeDefaults(formatRuntimeDefaults(value))).toEqual(value);
});

test("quick fields preserve scope, source contexts, overlays and extended defaults", () => {
  const source = {
    time: { mode: "live", range: { kind: "relative", duration_ms: 300000 } },
    scope: { primary: { kind: "contact", mode: "one", ids: ["contact-1"] } },
    data: { realm: "flight", source_contexts: { telemetry: { source_binding_id: "binding-1" } } },
    overlays: { quality: true },
    extension: { value: "preserved" },
  };
  const next = parseRuntimeDefaults(
    setRuntimeDefault(JSON.stringify(source), "time", "mode", "archive"),
  );
  expect(next).toEqual({ ...source, time: { ...source.time, mode: "archive" } });
  expect(parseRuntimeDefaults(setRuntimeDefault(JSON.stringify(next), "time", "mode", ""))).toEqual(
    { ...source, time: { range: source.time.range } },
  );
});

test("JSON admission bounds the complete document without coercing invalid values", () => {
  expect(parseRuntimeDefaults("{}")).toEqual({});
  for (const value of [
    "null",
    "[]",
    "true",
    "",
    "{",
    '{"number":1e400}',
    '{"number":9007199254740992}',
    JSON.stringify({ text: "x".repeat(4097) }),
    JSON.stringify({ items: Array(101).fill(0) }),
    JSON.stringify(Object.fromEntries(Array.from({ length: 65 }, (_, i) => [i, 0]))),
    " ".repeat(32769) + "{}",
    JSON.stringify({ ["x".repeat(257)]: 1 }),
    JSON.stringify(Array.from({ length: 9 }).reduce((value) => ({ nested: value }), {})),
  ]) {
    expect(() => parseRuntimeDefaults(value)).toThrow();
  }
});

test("a malformed context cannot be silently replaced by a quick field", () => {
  expect(() => setRuntimeDefault('{"time":[1]}', "time", "mode", "live")).toThrow();
  expect(
    parseRuntimeDefaults(
      setRuntimeDefault('{"__proto__":{"private":true}}', "time", "mode", "live"),
    ),
  ).toEqual(JSON.parse('{"__proto__":{"private":true},"time":{"mode":"live"}}'));
  expect(fixtureRecord({}).private).toBeUndefined();
});
