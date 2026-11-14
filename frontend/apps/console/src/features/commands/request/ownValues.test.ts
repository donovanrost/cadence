import { describe, expect, it } from "vite-plus/test";
import { groupOf, showBody } from "../groups/fixtures.ts";
import {
  cellOf,
  overridesOf,
  ownValuesText,
  radiateMeta,
  rawEntries,
  readoutLines,
  tableArgs,
  valueRange,
} from "./ownValues.ts";

const command = (perTarget: { spacecraft_id: string; argument_values_json: string }[]) => ({
  ...showBody.commands[0],
  name: "SET_TEMP",
  argument_values_json: '{"setpoint":8.0,"mode":1}',
  per_target: perTarget,
});
const target = (id: string, name: string) => ({
  ...showBody.targets[0],
  spacecraft_id: id,
  name,
});
/** A group of `n` targets where the given ones send their own values (decoded, as read). */
const groupWith = (n: number, own: { spacecraft_id: string; argument_values_json: string }[]) =>
  groupOf({
    target_count: n,
    targets: Array.from({ length: n }, (_, i) => target(`sc-${i + 1}`, `EARENDIL-${i + 1}`)),
    commands: [command(own)],
  });
const nameOf = (id: string) => id.replace("sc-", "EARENDIL-");

describe("targets with their own values (ux C2)", () => {
  it("reads values as sent, so 8.0 stays 8.0", () => {
    expect(rawEntries('{"setpoint":8.0,"mode":"low","list":[1,2]}')).toEqual(
      new Map([
        ["setpoint", "8.0"],
        ["mode", '"low"'],
        ["list", "[1,2]"],
      ]),
    );
    expect(rawEntries("{}")).toEqual(new Map());
    expect(rawEntries("[1]")).toBeNull();
    expect(valueRange(["9.5", "8.5", "9.0"])).toBe("8.5–9.5");
    expect(valueRange(["8.0", "8.0"])).toBe("8.0");
    expect(valueRange(['"low"', '"high"'])).toBe('"low" · "high"');
  });

  it("50 targets, 3 overrides: the shared line, then the own-values line", () => {
    const g = groupWith(50, [
      { spacecraft_id: "sc-9", argument_values_json: '{"setpoint":9.5,"mode":1}' },
      { spacecraft_id: "sc-2", argument_values_json: '{"setpoint":8.5,"mode":1}' },
      { spacecraft_id: "sc-4", argument_values_json: '{"setpoint":9.0}' },
    ]);
    const c = g.commands[0];
    if (!c) throw new Error("command");
    const o = overridesOf(c, g);
    expect(o.map((x) => x.spacecraftId)).toEqual(["sc-2", "sc-4", "sc-9"]);
    expect(readoutLines({ name: "setpoint", to: "8.0", from: "5.0" }, o, 50, "°C", nameOf)).toEqual(
      ["setpoint: 5.0 → 8.0 °C · on 47 spacecraft", "3 with their own values · 8.5–9.5 °C"],
    );
    expect(radiateMeta(g)).toBe(
      "Same for all 50 except SEQ and CRC; 3 targets encode their own values",
    );
    expect(tableArgs(c, o)).toEqual(["setpoint", "mode"]);
    const shared = rawEntries(c.argument_values_json);
    const sc4 = o[1];
    const sc2 = o[0];
    if (!sc4 || !sc2) throw new Error("overrides");
    expect(cellOf(sc4, "mode", shared, undefined)).toEqual({
      text: "default",
      kind: "default",
      caution: null,
    });
    expect(cellOf(sc2, "mode", shared, undefined).kind).toBe("same");
    expect(cellOf(sc2, "setpoint", shared, undefined).kind).toBe("differs");
  });

  it("every target overridden: no shared line; one target: its values and its name", () => {
    const all = groupWith(2, [
      { spacecraft_id: "sc-1", argument_values_json: '{"setpoint":8.0}' },
      { spacecraft_id: "sc-2", argument_values_json: '{"setpoint":9.5}' },
    ]);
    const c = all.commands[0];
    if (!c) throw new Error("command");
    expect(
      readoutLines(
        { name: "setpoint", to: "8.0", from: "5.0–6.2" },
        overridesOf(c, all),
        2,
        "°C",
        nameOf,
      ),
    ).toEqual(["setpoint: 5.0–6.2 → 8.0–9.5 °C · each of 2 with its own values"]);
    const one = groupWith(1, [{ spacecraft_id: "sc-1", argument_values_json: '{"setpoint":8.5}' }]);
    const c1 = one.commands[0];
    if (!c1) throw new Error("command");
    expect(
      readoutLines(
        { name: "setpoint", to: "8.0", from: "5.0" },
        overridesOf(c1, one),
        1,
        "°C",
        nameOf,
      ),
    ).toEqual(["setpoint: 5.0 → 8.5 °C · EARENDIL-1"]);
    expect(ownValuesText(c1, "sc-1")).toBe("setpoint 8.5");
    expect(ownValuesText(c1, "sc-9")).toBeNull();
  });

  it("Uplink words own values as Approve does: catalog order, units, strings unquoted", () => {
    const g = groupWith(2, [
      { spacecraft_id: "sc-1", argument_values_json: '{"mode":"low","setpoint":9.5,"extra":3}' },
    ]);
    const c = g.commands[0];
    if (!c) throw new Error("command");
    const args = [
      { name: "setpoint", unit: "°C" },
      { name: "mode", unit: null },
    ];
    expect(ownValuesText(c, "sc-1", args)).toBe("setpoint 9.5 °C · mode low · extra 3");
  });

  it("no overrides: the line as today, and no A3 addition", () => {
    const g = groupWith(3, []);
    const c = g.commands[0];
    if (!c) throw new Error("command");
    expect(
      readoutLines(
        { name: "setpoint", to: "8.0", from: "5.0" },
        overridesOf(c, g),
        3,
        null,
        nameOf,
      ),
    ).toEqual(["setpoint: 5.0 → 8.0"]);
    expect(radiateMeta(g)).toBeNull();
  });
});
