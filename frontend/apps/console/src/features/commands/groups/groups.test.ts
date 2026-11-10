import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import type { CommandArgument, CommandDetail } from "../api.ts";
import { argumentValuesJson, buildDraft } from "../compose/draft.ts";
import { splitArgs } from "../compose/resend.ts";
import { newItem } from "../compose/stack.ts";
import { resendFrom } from "../compose/useResend.ts";
import { EMPTY_QUERY } from "../compose/targets.ts";
import { fetchGroups, groupRow, preflightReader, type Preflight } from "./api.ts";
import { checkMeta, checkRows, noGoReason, routingProfile } from "./checks.ts";
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
    expect(rows[2]?.sentence).toBe("No booked contact with a confirmed uplink for SC-2 (SCID 8) in the release window");
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
      const r = await fetchGroups("m", {});
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
