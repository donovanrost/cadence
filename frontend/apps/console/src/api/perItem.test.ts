import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decoders as d, decode, oneItem, perItem, unshownLine } from "@/api/index.ts";

const thing = d.object({ id: d.token, kind: d.oneOf(["a", "b"] as const), n: d.integer });
const list = perItem(thing, 10, { label: "Things", kindOf: (raw) => [raw["kind"]] });

afterEach(() => vi.restoreAllMocks());

/** U86 (lead): strict per item, tolerant only at the list boundary. */
describe("perItem", () => {
  it("keeps the readable items and describes the rest by kind and id, never the payload", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const r = list([
      { id: "t-1", kind: "a", n: 1 },
      { id: "t-2", kind: "b", n: "SECRET-PAYLOAD" },
      { id: "t-3", kind: "b", n: 3 },
    ]);
    expect(r.items.map((t) => t.id)).toEqual(["t-1", "t-3"]);
    expect(r.unshown).toEqual([{ kind: ["b"], id: "t-2" }]);
    expect(warn).toHaveBeenCalledTimes(1);
    const said = String(warn.mock.calls[0]?.[0]);
    expect(said).toContain("Things: an item isn't shown (b, t-2)");
    expect(said).toContain("[1].n: expected finite number");
    expect(said).not.toContain("SECRET-PAYLOAD");
  });

  it("an item with no readable kind or id is still counted", () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const r = list([7, { kind: 4 }, { id: "t-9", kind: "a" }]);
    expect(r.items).toEqual([]);
    expect(r.unshown).toEqual([
      { kind: [], id: null },
      { kind: [], id: null },
      { kind: ["a"], id: "t-9" },
    ]);
  });

  it("the list itself stays strict: not an array, or too long, fails the read", () => {
    expect(decode(list, { items: [] }).ok).toBe(false);
    expect(
      decode(
        list,
        Array.from({ length: 11 }, () => ({})),
      ).ok,
    ).toBe(false);
  });

  it("shown() leaves out an item that reads but has nothing to draw, and counts it", () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const only = perItem(thing, 10, {
      label: "Things",
      kindOf: (raw) => [raw["kind"]],
      shown: (t) => t.kind === "a",
    });
    const r = only([
      { id: "t-1", kind: "a", n: 1 },
      { id: "t-2", kind: "b", n: 2 },
    ]);
    expect(r.items.map((t) => t.id)).toEqual(["t-1"]);
    expect(r.unshown).toEqual([{ kind: ["b"], id: "t-2" }]);
  });

  it("oneItem reads a single value the same way", () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const one = oneItem(thing, { label: "Thing", kindOf: (raw) => [raw["kind"]] });
    expect(one({ id: "t-1", kind: "a", n: 1 }).items).toHaveLength(1);
    expect(one({ id: "t-2", kind: "a" }).unshown).toEqual([{ kind: ["a"], id: "t-2" }]);
  });

  it("words each line as ux U86 has it", () => {
    expect(unshownLine({ kind: ["attention", "contact_start"], id: "x-1" })).toBe(
      "attention, contact_start, x-1",
    );
    expect(unshownLine({ kind: [], id: "x-1" })).toBe("An item with no readable kind, x-1");
    expect(unshownLine({ kind: [], id: null })).toBe("An item with no readable kind");
  });
});
