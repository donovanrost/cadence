import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import {
  fromDocument,
  kindSchemaReader,
  type FormState,
  type FormValues,
} from "@/features/changes/index.ts";
import { LISTENER, STOPS_SHARING, listenerRules } from "./listener.ts";

/** api's transport schema for U83: mode, direction, then the listener shown on listen + inbound. */
const select = (path: string, label: string, options: readonly [string, string][]) => ({
  path,
  label,
  type: "enum",
  unit: null,
  enum: options.map(([value, text]) => ({ value, label: text })),
  range: null,
  default: options[0]?.[0] ?? null,
  required: false,
  help: null,
  visible_when: null,
});
const read = decode(kindSchemaReader, {
  kind: "transport",
  fields: [
    select("configuration.mode", "TCP Mode", [
      ["listen", "TCP server (listen)"],
      ["connect", "TCP client (connect)"],
    ]),
    select("configuration.direction_capability", "Direction", [
      ["inbound", "Downlink"],
      ["outbound", "Uplink"],
      ["bidirectional", "Both"],
    ]),
    {
      ...select(LISTENER, "Listener", [
        ["own", "Own listener for each pass"],
        ["shared", "Shared, routed by SCID"],
      ]),
      visible_when: {
        all: [
          { path: "configuration.mode", equals: "listen" },
          { path: "configuration.direction_capability", equals: "inbound" },
        ],
      },
    },
  ],
});
if (!read.ok) throw read.error;
const schema = read.value;

const stored = (listener?: string) =>
  fromDocument(schema, {
    configuration: { mode: "listen", direction_capability: "inbound", listener },
  });
const state = (before: FormValues, edit: Readonly<Record<string, string>>): FormState => {
  const s = { schema, before, values: { ...before, ...edit } };
  return { ...s, values: listenerRules.reconcile?.(s) ?? s.values };
};
const finish = (s: FormState, changes: readonly { path: string; value: unknown }[]) =>
  listenerRules.finish?.(changes, s) ?? changes;

describe("a transport's listener (U83)", () => {
  it("sends own when an edit hides a stored shared listener, with the reason", () => {
    const s = state(stored("shared"), { "configuration.mode": "connect" });
    const changes = finish(s, [{ path: "configuration.mode", value: "connect" }]);
    expect(changes).toEqual([
      { path: "configuration.mode", value: "connect" },
      { path: LISTENER, value: "own" },
    ]);
    expect(listenerRules.describe?.({ path: LISTENER, value: "own" }, s)).toBe(
      "Listener: Shared, routed by SCID → Own listener for each pass (only a downlink transport that listens can share one)",
    );
    expect(listenerRules.notes?.(s)).toEqual({ "configuration.mode": STOPS_SHARING });
  });

  it("puts the line under the direction when that's what changed", () => {
    const s = state(stored("shared"), { "configuration.direction_capability": "outbound" });
    expect(listenerRules.notes?.(s)).toEqual({
      "configuration.direction_capability": STOPS_SHARING,
    });
  });

  it("shows Own chosen and drops the line when switched back before staging", () => {
    const hidden = state(stored("shared"), { "configuration.mode": "connect" });
    const back = state(stored("shared"), { ...hidden.values, "configuration.mode": "listen" });
    expect(back.values[LISTENER]).toBe("own");
    expect(listenerRules.notes?.(back)).toEqual({});
    expect(listenerRules.describe?.({ path: LISTENER, value: "own" }, back)).toBe(
      "Listener: Shared, routed by SCID → Own listener for each pass",
    );
  });

  it("sends nothing for a hidden listener that was never shared", () => {
    const s = state(stored(), { "configuration.mode": "connect" });
    expect(finish(s, [{ path: "configuration.mode", value: "connect" }])).toEqual([
      { path: "configuration.mode", value: "connect" },
    ]);
    expect(listenerRules.notes?.(s)).toEqual({});
  });

  it("never sends own over a missing key, and sends shared as chosen", () => {
    const own = state(stored(), { [LISTENER]: "own" });
    expect(finish(own, [{ path: LISTENER, value: "own" }])).toEqual([]);
    const shared = state(stored(), { [LISTENER]: "shared" });
    expect(finish(shared, [{ path: LISTENER, value: "shared" }])).toEqual([
      { path: LISTENER, value: "shared" },
    ]);
    expect(listenerRules.describe?.({ path: LISTENER, value: "shared" }, shared)).toBe(
      "Listener: Own listener for each pass → Shared, routed by SCID",
    );
  });

  it("leaves other changes' summary words to the form", () => {
    const s = state(stored(), { "configuration.mode": "connect" });
    expect(listenerRules.describe?.({ path: "configuration.mode", value: "connect" }, s)).toBe(
      null,
    );
  });
});
