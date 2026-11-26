import { describe, expect, it } from "vite-plus/test";
import { getAt, setAt } from "./json.ts";

/** #192: the console's one dotted schema-path read and write. */
describe("getAt / setAt", () => {
  it("reads and writes a nested path", () => {
    const doc: Record<string, unknown> = { frame_parameters: { frame_size: 1115 } };
    expect(getAt(doc, "frame_parameters.frame_size")).toBe(1115);
    setAt(doc, "frame_parameters.frame_size", 2048);
    expect(getAt(doc, "frame_parameters.frame_size")).toBe(2048);
  });

  it("reads undefined through a missing parent, and creates it on write", () => {
    const doc: Record<string, unknown> = {};
    expect(getAt(doc, "a.b.c")).toBeUndefined();
    setAt(doc, "a.b.c", 1);
    expect(doc).toEqual({ a: { b: { c: 1 } } });
  });

  it("reads undefined through a non-object value, and replaces it on write", () => {
    const doc: Record<string, unknown> = { a: 5, list: [1, 2] };
    expect(getAt(doc, "a.b")).toBeUndefined();
    expect(getAt(doc, "list.0")).toBeUndefined();
    setAt(doc, "a.b", "x");
    expect(doc["a"]).toEqual({ b: "x" });
  });

  it("never changes a nested object it shares with another document (copy-on-write)", () => {
    const carried = { frame_parameters: { frame_size: 1115, mode: "fixed" } };
    const doc: Record<string, unknown> = { ...carried };
    setAt(doc, "frame_parameters.frame_size", 2048);
    expect(carried.frame_parameters.frame_size).toBe(1115);
    expect(doc).toEqual({ frame_parameters: { frame_size: 2048, mode: "fixed" } });
  });
});
