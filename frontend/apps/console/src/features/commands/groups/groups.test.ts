import { describe, expect, it } from "vite-plus/test";
import { missionId as missionIdReader, decode } from "@/api/index.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import type { CommandArgument, CommandDetail } from "../api.ts";
import { argumentValuesJson, buildDraft } from "../compose/draft.ts";
import { splitArgs } from "../compose/resend.ts";
import {
  addToCurrent,
  checkItem,
  clearPerTarget,
  fillFromCurrent,
  fillFromForm,
  newItem,
  pastePerTargetCsv,
  setPerTargetMode,
  setTargetValue,
} from "../compose/stack.ts";
import { resendFrom } from "../compose/useResend.ts";
import { EMPTY_QUERY } from "../compose/targets.ts";
import { fetchGroups, groupRow, preflightReader, type Preflight } from "./api.ts";
import { memberStageWord } from "./words.ts";
import { checkMeta, checkRows, noGoReason, routingProfile } from "./checks.ts";
import { groupOf, showBody } from "./fixtures.ts";
import { groupReader } from "./show.ts";
import {
  notPlottable,
  plotSentence,
  seriesChart,
  seriesMeta,
  type VerifierSeries,
} from "./series.ts";
import { onlyFrom } from "../compose/useResend.ts";
import { fetchEncoding, hexBytes } from "./encoding.ts";

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
    current_point: undefined,
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
      expiresAt: null,
      priority: 3,
      approver: "",
      sentBackFrom: null,
      endpoints: { "spacecraft-earendil-002": "ep-2" },
    });
    expect(draft).toMatchObject({
      title: "Reset counters",
      targets: [
        { spacecraft_id: "spacecraft-earendil-001", source_endpoint_id: null },
        { spacecraft_id: "spacecraft-earendil-002", source_endpoint_id: "ep-2" },
      ],
      target_query: { chips: [{ key: "plane", value: 1 }], explicit: [] },
      commands: [{ command_id: "cmd-1", argument_values_json: '{"count":3}' }],
      not_before: "2026-11-08T04:00:00.000Z",
      requested_approver_user_id: null,
    });
  });

  it("sends a target's own values as per_target, only for targets that have them (B2)", () => {
    const item = newItem(
      command([arg({ id: "n", name: "count" }), arg({ id: "m", name: "mode" })]),
    );
    const base = {
      title: "t",
      log: "",
      targets: [spacecraftRow(1), spacecraftRow(2), spacecraftRow(3)],
      query: EMPTY_QUERY,
      notBefore: null,
      expiresAt: null,
      priority: 3,
      approver: "",
      sentBackFrom: null,
      endpoints: {},
    };
    const draft = buildDraft({
      ...base,
      stack: [
        {
          ...item,
          values: { n: "3", m: "1" },
          // EARENDIL-002 has its own count; 003 is listed but inherits; a removed target is ignored.
          perTarget: { n: { "spacecraft-earendil-002": "8", "spacecraft-earendil-404": "9" } },
        },
      ],
    });
    expect(draft?.commands).toEqual([
      {
        command_id: "cmd-1",
        argument_values_json: '{"count":3,"mode":1}',
        per_target: [
          {
            spacecraft_id: "spacecraft-earendil-002",
            argument_values_json: '{"count":8,"mode":1}',
          },
        ],
      },
    ]);
    // An invalid per-target value blocks the draft, as an invalid form value does.
    expect(
      buildDraft({
        ...base,
        stack: [
          {
            ...item,
            values: { n: "3", m: "1" },
            perTarget: { n: { "spacecraft-earendil-002": "x" } },
          },
        ],
      }),
    ).toBeNull();
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
    expect(rows[2]?.sentence).toBe(
      "No booked contact with a confirmed uplink for SC-2 (SCID 8) in the release window",
    );
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

describe("identity via routes (DECISIONS #41)", () => {
  it("names the routing failure and links to the profile's routing", () => {
    const decoded = decode(preflightReader, {
      ...body,
      checks: [
        {
          key: "identity",
          result: "no_go",
          per_target: [
            {
              spacecraft_id: "sc-1",
              result: "no_go",
              reason: "multiple_primary_uplink_routes",
              routes: [
                { id: "r1", name: "SVL S-band", direction: "outbound", profile_id: "prof-1" },
                { id: "r2", name: "AWA S-band", direction: "bidirectional", profile_id: "prof-1" },
              ],
            },
          ],
          evidence: { count: 1 },
        },
      ],
    });
    if (!decoded.ok) throw decoded.error;
    const [row] = checkRows(decoded.value, () => "SC-1 (SCID 7)");
    expect(row?.sentence).toBe("SC-1 (SCID 7) has several primary uplink routes");
    expect(row?.profileId).toBe("prof-1");
    expect(decoded.value.checks[0] && routingProfile(decoded.value.checks[0])).toBe("prof-1");
  });
});

describe("group list", () => {
  it("decodes live rows: progress/finished null unless queued (cfef9e9a)", () => {
    const base = {
      id: "g",
      title: "t",
      requested_by: { actor_kind: "user", user_id: "u" },
      requested_at: "2026-11-09T15:26:26.296234Z",
      requested_approver_user_id: null,
      member_count: 1,
      target_count: 1,
      command_count: 1,
      second_go_required: false,
      awaiting_me: false,
      operation_id: null,
    };
    expect(
      decode(groupRow, { ...base, state: "rejected", progress: null, finished: null }).ok,
    ).toBe(true);
    const q = decode(groupRow, {
      ...base,
      state: "queued",
      progress: { no_verifier: 1 },
      finished: true,
    });
    expect(q.ok && q.value.finished).toBe(true);
  });

  it("unwraps {groups: [...]}", async () => {
    const original = globalThis.fetch;
    globalThis.fetch = () =>
      Promise.resolve(new Response(JSON.stringify({ data: { groups: [] } }), { status: 200 }));
    try {
      const r = await fetchGroups(missionIdReader("m"), {});
      expect(r).toEqual({ ok: true, value: [] });
    } finally {
      globalThis.fetch = original;
    }
  });
});

describe("resend", () => {
  it("splits argument JSON without losing 64-bit values", () => {
    expect(splitArgs('{"count":18446744073709551615, "mode":"SAFE","on":true,"x":-1.5e3}')).toEqual(
      {
        count: "18446744073709551615",
        mode: '"SAFE"',
        on: "true",
        x: "-1.5e3",
      },
    );
    expect(splitArgs("{}")).toEqual({});
    expect(splitArgs('{"a":[1]}')).toBeNull();
    expect(splitArgs('{"a":1} trailing')).toBeNull();
  });

  it("reads ?from=group:<id>", () => {
    expect(resendFrom("group:grp-1")).toBe("grp-1");
    expect(resendFrom("group:")).toBeNull();
    expect(resendFrom(undefined)).toBeNull();
  });
});

describe("M24 encode preview", () => {
  it("shows bytes in pairs and reads a fail-closed 409 as words", async () => {
    expect(hexBytes("0a0007")).toBe("0A 00 07");
    const original = globalThis.fetch;
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            error: {
              code: "encode_unavailable",
              message: "x",
              details: { reason: "revision_superseded", detail: null },
            },
          }),
          { status: 409 },
        ),
      );
    try {
      expect(await fetchEncoding(missionIdReader("m"), "r")).toEqual({
        ok: false,
        reason: "the catalog revision it was submitted against has been superseded",
      });
    } finally {
      globalThis.fetch = original;
    }
  });
});

describe("M26 verifier series (U2)", () => {
  const base: VerifierSeries = {
    telemetry: undefined,
    points: undefined,
    verifier: { position: 1, command_id: "c", command_name: "SET_TEMP" },
    point: { id: "THERM.sp", name: "batt_setpoint", unit: "°C", type: "numeric" },
    reason: null,
    commanded: { value_json: "8.0", comparison: "eq" },
    band: null,
    window: { from: "2026-11-10T01:00:00Z", to: "2026-11-10T01:05:00Z" },
    targets: [
      {
        spacecraft_id: "a",
        name: "A",
        verifier_state: "satisfied",
        verifier: undefined,
        timeout_at: undefined,
        matched_at: undefined,
        samples: [{ t: "2026-11-10T01:01:00Z", value_json: "8.0" }],
      },
      {
        spacecraft_id: "b",
        name: "B",
        verifier_state: "failed",
        verifier: undefined,
        timeout_at: undefined,
        matched_at: undefined,
        samples: [{ t: "2026-11-10T01:01:00Z", value_json: "5.0" }],
      },
    ],
    target_count: 2,
    truncated: false,
    summary: { met: 1, not_met: 1, pending: 0 },
  };
  it("headers, plots, and says why not when it can't", () => {
    expect(seriesMeta(base)).toBe("02 SET_TEMP · 1 met 8.0 · 1 did not");
    const chart = seriesChart(base);
    expect(chart?.lines.map((l) => [l.tone, l.dash, l.points.length])).toEqual([
      ["text-4", "solid", 1],
      ["text-2", "solid", 1],
      ["readout", "dashed", 2],
    ]);
    expect(
      notPlottable({ ...base, point: null, reason: "verified_by_uplink_acknowledgement" }),
    ).toBe("Not plottable: verified by uplink acknowledgement only");
    expect(notPlottable({ ...base, window: null })).toBe(
      "Nothing to plot until the first uplink is released",
    );
  });
  it("names a target with no name Unknown spacecraft, never its id (#237)", () => {
    const [a, b] = base.targets;
    if (!a || !b) throw new Error("fixture");
    const nameless = { ...base, targets: [{ ...a, name: null }, b] };
    expect(seriesChart(nameless)?.lines.map((l) => l.name)).toContain("Unknown spacecraft");
    expect(plotSentence(nameless)).toContain("Unknown spacecraft and B");
    expect(plotSentence(nameless)).not.toContain("a and");
  });
  it("Re-send narrows to ?only=", () => {
    expect(onlyFrom("a,b")).toEqual(["a", "b"]);
    expect(onlyFrom(undefined)).toEqual([]);
  });
});

describe("L22 archived spacecraft (ux U40)", () => {
  it("words a member canceled because its spacecraft was archived, by name", () => {
    expect(memberStageWord("canceled", "queued", "spacecraft_archived", "EARENDIL-004")).toBe(
      "Not released: EARENDIL-004 is archived",
    );
    expect(memberStageWord("canceled", "queued", "spacecraft_archived")).toBe(
      "Not released: the spacecraft is archived",
    );
  });
});

describe("E2 withdrawn after GO (#546, #1019)", () => {
  it("words a member the lane refused because the model's approval was withdrawn after GO", () => {
    expect(memberStageWord("canceled", "queued", "model_approval_withdrawn_after_go")).toBe(
      "Not released: the model's approval was withdrawn after GO",
    );
    // The reason decodes as a known end reason, not an unrecognized one.
    const g = groupOf({
      state: "queued",
      targets: [
        {
          ...showBody.targets[0],
          stage: "canceled",
          members: [
            {
              ...showBody.targets[0]?.members[0],
              stage: "canceled",
              end_reason: "model_approval_withdrawn_after_go",
            },
          ],
        },
      ],
    });
    expect(g.targets[0]?.members[0]?.end_reason).toBe("model_approval_withdrawn_after_go");
  });
});

describe("B2 per-target values (CommandFlow.md C1)", () => {
  const item = {
    ...newItem(
      command([
        arg({ id: "n", name: "count", valid_range: { minimum_json: "0", maximum_json: "10" } }),
        arg({ id: "m", name: "mode" }),
      ]),
    ),
    values: { n: "3", m: "1" },
  };
  const ids = ["spacecraft-earendil-001", "spacecraft-earendil-002"];
  const targets = [spacecraftRow(1), spacecraftRow(2)];

  it("switches an argument to Per target and back, forgetting its values", () => {
    const on = { ...item, perTarget: setPerTargetMode(item, "n", true) };
    expect(on.perTarget).toEqual({ n: {} });
    const set = { ...on, perTarget: setTargetValue(on, "n", ids[1] ?? "", "8") };
    expect(set.perTarget).toEqual({ n: { "spacecraft-earendil-002": "8" } });
    // Empty inherits again.
    expect(setTargetValue(set, "n", ids[1] ?? "", "")).toEqual({ n: {} });
    expect(setPerTargetMode(set, "n", false)).toEqual({});
  });

  it("fills every target from the form, and clears back to inheriting", () => {
    const on = { ...item, perTarget: { n: { "spacecraft-earendil-002": "8" } } };
    expect(fillFromForm(on, ids)).toEqual({
      n: { "spacecraft-earendil-001": "3", "spacecraft-earendil-002": "3" },
    });
    expect(clearPerTarget(on)).toEqual({ n: {} });
  });

  it("pastes CSV by SCID or name, in the Per-target arguments' order, and reports the rest", () => {
    const on = { ...item, perTarget: { n: {}, m: {} } };
    const r = pastePerTargetCsv(on, "1, 7, 2\nEARENDIL-002, , 5\n999, 1, 1\n", targets);
    expect(r.perTarget).toEqual({
      n: { "spacecraft-earendil-001": "7" },
      m: { "spacecraft-earendil-001": "2", "spacecraft-earendil-002": "5" },
    });
    expect(r.unmatched).toEqual(["999"]);
  });

  it("marks a target's out-of-range value and blocks the item", () => {
    const on = { ...item, perTarget: { n: { "spacecraft-earendil-002": "40" } } };
    const check = checkItem(on, ids);
    expect(check.ok).toBe(false);
    expect(Object.keys(check.targetErrors.n ?? {})).toEqual(["spacecraft-earendil-002"]);
    // A target outside the request doesn't count.
    expect(checkItem(on, ["spacecraft-earendil-001"]).ok).toBe(true);
  });
});

describe("B2 Now column and Current + (api, per-target values)", () => {
  it("adds to the current value at the inputs' precision; non-numbers don't add", () => {
    expect(addToCurrent("7.5", "2.0")).toBe("9.5");
    expect(addToCurrent("20", "-0.25")).toBe("19.75");
    expect(addToCurrent('"SAFE"', "1")).toBeNull();
  });
  it("fills each target from its current value, only where the units match", () => {
    const base = newItem(
      command([
        arg({ id: "t", name: "setpoint", type: "float", unit: "degC" }),
        arg({ id: "r", name: "rate", type: "float", unit: "Hz" }),
      ]),
    );
    const item = {
      ...base,
      command: {
        ...base.command,
        arguments: base.command.arguments.map((a) =>
          a.id === "t"
            ? { ...a, current_point: { id: "THERM.sp", name: "THERM.sp", unit: "degC" } }
            : { ...a, current_point: { id: "X.rate", name: "X.rate", unit: "rpm" } },
        ),
      },
      values: { t: "2.0", r: "1" },
      perTarget: { t: {}, r: {} },
    };
    const current = new Map([
      [
        "t",
        new Map([
          ["sc-1", "7.5"],
          ["sc-2", null],
        ]),
      ],
      ["r", new Map([["sc-1", "3"]])],
    ]);
    expect(fillFromCurrent(item, ["sc-1", "sc-2"], current)).toEqual({
      t: { "sc-1": "9.5" },
      r: {},
    });
  });
});

describe("a member whose release window passed (parity D4)", () => {
  it("reads 'Expired', never 'Canceled'", async () => {
    const { memberStageWord } = await import("./words.ts");
    expect(memberStageWord("canceled", "queued", "expired")).toBe("Expired");
    expect(memberStageWord("canceled", "queued", null)).toBe("Canceled");
  });
});
