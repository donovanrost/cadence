import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/index.ts";
import type { CommandDetail } from "../api.ts";
import {
  verifierLine,
  argSummary,
  checkItem,
  move,
  moveTo,
  newItem,
  secondGoReasons,
} from "./stack.ts";
import {
  chipWords,
  EMPTY_QUERY,
  leftQueryWords,
  queryFromRoute,
  resolveTargets,
} from "./targets.ts";

const fleet = [
  spacecraftRow(1),
  spacecraftRow(26, { state: "caution" }),
  spacecraftRow(27),
  spacecraftRow(312, { plane: 13, state: "critical" }),
];

function command(overrides: Partial<CommandDetail> = {}): CommandDetail {
  return {
    id: "cmd-1",
    name: "SET_HEATER_SETPOINT",
    display_name: null,
    description: null,
    subsystem: null,
    group: null,
    significance: "routine",
    critical: false,
    hazardous: false,
    second_go_required: false,
    argument_count: 2,
    opcode_json: "18",
    apid: 0,
    release_policy_hint: null,
    arguments: [
      {
        id: "h",
        name: "heater_id",
        description: null,
        type: "enumerated",
        required: true,
        default_value_json: null,
        fixed_value_json: null,
        hazardous_values_json: [],
        choices: [{ label: "1", value_json: "1" }],
        valid_range: null,
        unit: null,
        current_point: undefined,
      },
      {
        id: "s",
        name: "setpoint",
        description: null,
        type: "float",
        required: true,
        default_value_json: "20.0",
        fixed_value_json: null,
        hazardous_values_json: [],
        choices: [],
        valid_range: { minimum_json: "-40.0", maximum_json: "60.0" },
        unit: "degC",
        current_point: undefined,
      },
    ],
    verifiers: [],
    ...overrides,
  };
}

describe("compose targets", () => {
  it("takes explicit spacecraft from ?targets=sc:<id>", () => {
    const q = queryFromRoute({ targets: "sc:spacecraft-earendil-312,junk" });
    expect(resolveTargets(fleet, q).map((sc) => sc.scid)).toEqual([312]);
  });

  it("narrows by chips (AND) and adds explicit ones", () => {
    const q = {
      ...EMPTY_QUERY,
      plane: 2,
      states: ["caution" as const],
      explicit: ["spacecraft-earendil-001"],
    };
    expect(resolveTargets(fleet, q).map((sc) => sc.scid)).toEqual([1, 26]);
    expect(resolveTargets(fleet, EMPTY_QUERY)).toEqual([]);
    expect(chipWords(q, (id) => id)).toEqual(["plane 02", "state caution"]);
  });
});

describe("compose stack", () => {
  it("starts from defaults and blocks invalid values", () => {
    const item = newItem(command());
    expect(item.values).toEqual({ h: "", s: "20.0" });
    expect(checkItem(item)).toMatchObject({
      ok: false,
      errors: { h: "Required." },
    });
    const filled = { ...item, values: { h: "1", s: "21.5" } };
    expect(checkItem(filled).ok).toBe(true);
    expect(argSummary(filled)).toEqual(["heater_id 1", "setpoint 21.5 degC"]);
  });

  it("moves rows and words the second-GO reasons (#31)", () => {
    expect(move(["a", "b", "c"], 0, 1)).toEqual(["b", "a", "c"]);
    expect(move(["a", "b"], 1, 1)).toEqual(["a", "b"]);
    const hazardous = newItem(
      command({ name: "FORCE_WATCHDOG", hazardous: true, second_go_required: true }),
    );
    expect(secondGoReasons([hazardous], 1, 10)).toEqual(["FORCE_WATCHDOG is hazardous"]);
    expect(secondGoReasons([newItem(command())], 12, 10)).toEqual([
      "12 targets is fleet reach (10 or more)",
    ]);
    expect(secondGoReasons([newItem(command())], 3, 10)).toEqual([]);
  });
});

describe("verifier line (ux Compose ruling #3)", () => {
  it("names completion verifiers and their window, or says it can't turn green", () => {
    expect(
      verifierLine({
        verifiers: [
          { name: "ACCEPTED", phase: "acceptance", timeout_ms: 5000 },
          { name: "MODE_CHANGED", phase: "completion", timeout_ms: 60_000 },
        ],
      }),
    ).toEqual({ text: "Verifies MODE_CHANGED within 60 s", verifiable: true });
    expect(verifierLine({ verifiers: [] })).toEqual({
      text: "No verifier: this command can't turn green",
      verifiable: false,
    });
  });
});

describe("Compose reorder and the live query (Command.md C1/C2)", () => {
  it("drags an item to a new place", () => {
    expect(moveTo(["a", "b", "c", "d"], 0, 2)).toEqual(["b", "c", "a", "d"]);
    expect(moveTo(["a", "b", "c"], 2, 0)).toEqual(["c", "a", "b"]);
    expect(moveTo(["a", "b"], 0, 5)).toEqual(["a", "b"]);
  });
  it("says who left the query and why", () => {
    const back = spacecraftRow(318, { name: "EARENDIL-318", state: "nominal" });
    expect(leftQueryWords([back])).toBe(
      "1 spacecraft no longer matches your targets: EARENDIL-318 is back in limits. Keep it in this request?",
    );
    const stale = spacecraftRow(2, { name: "B", state: "stale" });
    expect(leftQueryWords([back, stale])).toBe(
      "2 spacecraft no longer match your targets: EARENDIL-318, B. Keep them?",
    );
    expect(leftQueryWords([])).toBeNull();
  });
});
