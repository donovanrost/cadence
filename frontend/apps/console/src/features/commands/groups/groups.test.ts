import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import type { CommandArgument, CommandDetail } from "../api.ts";
import { argumentValuesJson, buildDraft } from "../compose/draft.ts";
import { newItem } from "../compose/stack.ts";
import { EMPTY_QUERY } from "../compose/targets.ts";
import { preflightReader, type Preflight } from "./api.ts";
import { checkMeta, checkRows, noGoReason } from "./checks.ts";
import { showBody } from "./fixtures.ts";
import { groupReader } from "./show.ts";

function arg(overrides: Partial<CommandArgument>): CommandArgument {
  return {
    id: "a",
    name: "a",
    description: null,
    type: "integer",
    required: true,
    default_value_json: null,
    fixed_value_json: null,
    hazardous_values_json: [],
    choices: [],
    valid_range: null,
    unit: null,
    ...overrides,
  };
}

function command(args: CommandArgument[]): CommandDetail {
  return {
    id: "cmd-1",
    name: "SET_COUNTER",
    display_name: null,
    description: null,
    subsystem: null,
    group: null,
    significance: "routine",
    critical: false,
    hazardous: false,
    second_go_required: false,
    argument_count: args.length,
    opcode_json: "18",
    apid: 0,
    release_policy_hint: null,
    arguments: args,
    verifiers: [],
  };
}

const body = {
  valid: false,
  digest: "abc",
  members: 2,
  second_go_required: true,
  targets: [
    {
      index: 0,
      spacecraft_id: "sc-1",
      source_endpoint_id: "ep-1",
      name: "SC-1",
      scid: 7,
      failure: null,
    },
  ],
  checks: [
    { key: "identity", result: "go", per_target: [], evidence: {} },
    {
      key: "catalog",
      result: "no_go",
      per_target: [
        {
          spacecraft_id: "sc-1",
          result: "no_go",
          reason: [{ position: 0, command_id: "cmd-1", reason: "invalid_command_argument" }],
        },
      ],
      evidence: { count: 1 },
    },
    {
      key: "contact",
      result: "hold",
      per_target: [
        {
          spacecraft_id: "sc-1",
          result: "go",
          next_contact: {
            station_code: "SVL",
            aos: "2026-11-08T03:00:00Z",
            los: "2026-11-08T03:12:00Z",
          },
        },
        { spacecraft_id: "sc-2", result: "hold", next_contact: null },
      ],
      evidence: { until: "2026-11-08T09:00:00Z" },
    },
    {
      key: "two_person",
      result: "hold",
      per_target: [],
      evidence: {
        reasons: [
          { key: "hazardous_command", command_id: "cmd-1", name: "SET_POWER_MODE" },
          { key: "fleet_reach", targets: 12, threshold: 10 },
        ],
      },
    },
    { key: "plan_impact", result: "go", per_target: [], evidence: {} },
  ],
};

function preflight(): Preflight {
  const decoded = decode(preflightReader, body);
  if (!decoded.ok) throw decoded.error;
  return decoded.value;
}

describe("group draft", () => {
  it("splices argument JSON so 64-bit integers survive; leaves fixed and empty optionals out", () => {
    const item = newItem(
      command([
        arg({ id: "n", name: "count" }),
        arg({ id: "f", name: "fixed", fixed_value_json: "1" }),
        arg({ id: "o", name: "opt", required: false }),
      ]),
    );
    const big = { ...item, values: { n: "18446744073709551615", o: "" } };
    expect(argumentValuesJson(big)).toBe('{"count":18446744073709551615}');
    expect(argumentValuesJson({ ...item, values: { n: "x" } })).toBeNull();
  });

  it("builds the draft with chips, release and approver", () => {
    const item = newItem(command([arg({ id: "n", name: "count" })]));
    const draft = buildDraft({
      title: " Reset counters ",
      log: "",
      targets: [spacecraftRow(1), spacecraftRow(2)],
      query: { ...EMPTY_QUERY, plane: 1 },
      stack: [{ ...item, values: { n: "3" } }],
      notBefore: Date.parse("2026-11-08T04:00:00Z"),
      approver: "",
      sentBackFrom: null,
    });
    expect(draft).toMatchObject({
      title: "Reset counters",
      targets: [
        { spacecraft_id: "spacecraft-earendil-001", source_endpoint_id: null },
        { spacecraft_id: "spacecraft-earendil-002", source_endpoint_id: null },
      ],
      target_query: { chips: [{ key: "plane", value: 1 }], explicit: [] },
      commands: [{ command_id: "cmd-1", argument_values_json: '{"count":3}' }],
      not_before: "2026-11-08T04:00:00.000Z",
      requested_approver_user_id: null,
    });
  });
});

describe("preflight", () => {
  it("decodes the contract shape, including unknown check keys", () => {
    expect(decode(preflightReader, body).ok).toBe(true);
    expect(
      decode(preflightReader, { ...body, checks: [{ ...body.checks[0], result: "maybe" }] }).ok,
    ).toBe(false);
  });

  it("writes poll rows with names, and the first NO-GO as the commit reason", () => {
    const pf = preflight();
    const nameOf = (id: string) => (id === "sc-1" ? "SC-1 (SCID 7)" : "SC-2 (SCID 8)");
    const rows = checkRows(pf, nameOf);
    expect(rows.map((r) => [r.label, r.verdict])).toEqual([
      ["Identity", "GO"],
      ["Catalog", "NO-GO"],
      ["Contact", "HOLD"],
      ["Two-person", "HOLD"],
      ["Plan impact", "GO"],
    ]);
    expect(rows[0]?.sentence).toBe("The target resolves · SCID 7");
    expect(rows[2]?.sentence).toBe("No booked contact for SC-2 (SCID 8): its uplink waits for one");
    expect(rows[3]?.sentence).toBe(
      "Needs a second operator's GO: SET_POWER_MODE is hazardous; 12 targets is fleet reach (10 or more)",
    );
    expect(checkMeta(pf)).toBe("2 GO · 2 HOLD · 1 NO-GO");
    expect(noGoReason(pf, nameOf)).toBe("Catalog NO-GO: Not valid on SC-1 (SCID 7).");
  });
});

describe("group show", () => {
  it("decodes the show shape and rejects unknown stages", () => {
    const ok = decode(groupReader, showBody);
    expect(ok.ok && ok.value.progress).toEqual({ awaiting_go: 2 });
    expect(decode(groupReader, { ...showBody, progress: { warping: 1 } }).ok).toBe(false);
  });
});
