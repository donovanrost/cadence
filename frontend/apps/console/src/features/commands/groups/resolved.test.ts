import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import {
  resolvedArgumentReader,
  resolvedByCommand,
  resolvedCell,
  resolvedLines,
  type ResolvedArgument,
} from "./resolved.ts";

const row = (o: Record<string, unknown>): ResolvedArgument => {
  const r = decode(resolvedArgumentReader, {
    name: "TIMEOUT",
    entered_value_json: null,
    resolved_value_json: "30",
    sent_value_json: null,
    unit: "s",
    source: "default",
    spacecraft_ids: null,
    ...o,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const nameOf = (id: string) => id.replace("sc-", "EARENDIL-");

describe("resolved arguments (ux U68, api R1)", () => {
  it("compares sent values at the entered value's decimal places (ux a150a527a)", async () => {
    const { sentDiffers } = await import("./resolved.ts");
    expect(sentDiffers("0.1", "0.100000001")).toBe(false);
    expect(sentDiffers("2.50", "2.5")).toBe(false);
    expect(sentDiffers("16777217", "16777216")).toBe(true);
    expect(sentDiffers("2.5", "2.6")).toBe(true);
    expect(sentDiffers('"A"', '"B"')).toBe(true);
  });
  it("words a filled default, hides single-precision noise, shows a real change, names targets", () => {
    expect(resolvedLines([row({})], nameOf)).toEqual(["TIMEOUT: default used, 30 s"]);
    expect(
      resolvedLines(
        [
          row({
            name: "VOLTAGE",
            entered_value_json: "0.1",
            resolved_value_json: "0.1",
            sent_value_json: "0.100000001",
            unit: "V",
            source: "entered",
          }),
        ],
        nameOf,
      ),
    ).toEqual([]);
    expect(
      resolvedLines(
        [
          row({
            name: "COUNT",
            entered_value_json: "16777217",
            resolved_value_json: "16777217",
            sent_value_json: "16777216",
            unit: null,
            source: "entered",
          }),
        ],
        nameOf,
      ),
    ).toEqual(["COUNT: sent as 16777216 (entered 16777217)"]);
    expect(
      resolvedLines([row({ source: "fixed", spacecraft_ids: ["sc-004", "sc-009"] })], nameOf),
    ).toEqual(["EARENDIL-004, EARENDIL-009 · TIMEOUT: fixed value used, 30 s"]);
    expect(resolvedLines(undefined, nameOf)).toEqual([]);
  });
  it("reads an unknown source as its own word", () => {
    expect(resolvedLines([row({ source: "profile" })], nameOf)).toEqual([
      "TIMEOUT: profile value used, 30 s",
    ]);
  });
  it("fills the own-values cell for the targets a row covers", () => {
    const rows = [
      row({ spacecraft_ids: ["sc-004"] }),
      row({
        name: "MODE",
        entered_value_json: '"A"',
        resolved_value_json: '"A"',
        sent_value_json: '"B"',
        unit: null,
        source: "entered",
      }),
    ];
    expect(resolvedCell(rows, "TIMEOUT", "sc-004")).toEqual({
      text: "default · 30 s",
      entered: null,
    });
    expect(resolvedCell(rows, "TIMEOUT", "sc-005")).toBeNull();
    expect(resolvedCell(rows, "MODE", "sc-005")).toEqual({ text: "B", entered: "entered A" });
  });
  it("lists Arm's lines per command in stack order, skipping commands with none", () => {
    const out = resolvedByCommand(
      [
        { position: 1, resolved_arguments: [row({})] },
        { position: 0, resolved_arguments: [] },
        { position: 2 },
      ],
      nameOf,
      (p) => ["NOOP", "SET_HEATER", "PING"][p] ?? "",
    );
    expect(out).toEqual([
      { position: 1, label: "2 · SET_HEATER", lines: ["TIMEOUT: default used, 30 s"] },
    ]);
  });
});
