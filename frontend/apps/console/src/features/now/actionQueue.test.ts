import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import {
  attentionMeta,
  attentionReader,
  attentionWords,
  newlyResolved,
  resolvedWords,
  withFading,
} from "./attention.ts";

const member = (scid: number, extra: Record<string, unknown> = {}) => ({
  id: `spacecraft-earendil-${String(scid).padStart(3, "0")}`,
  name: `EARENDIL-${String(scid).padStart(3, "0")}`,
  scid,
  plane: 13,
  stale: false,
  last_received_at: null,
  violating_points: 1,
  value: 23.1,
  first_crossed_at: "2026-11-08T02:35:02Z",
  episode_id: null,
  status: null,
  assignee: null,
  acknowledged_by: null,
  ...extra,
});
const item = (overrides: Record<string, unknown>) => ({
  id: "x",
  priority: 1,
  kind: "alarm",
  state: "critical",
  source: null,
  acknowledged: null,
  since: null,
  due_at: null,
  count: 1,
  spacecraft: [],
  point: null,
  condition: null,
  plane: null,
  command: null,
  outcome: null,
  command_requests: [],
  finding: null,
  ...overrides,
});
const body = (items: unknown[]) => ({
  observed_at: "2026-11-08T02:41:17Z",
  stale_after_s: 900,
  failure_lookback_s: 86400,
  counts: { p1: 1, p2: 0, p3: 0, spacecraft_p1: 1 },
  items,
});
const present = (items: unknown[]) => {
  const result = decode(actionQueueReader, body(items));
  if (!result.ok) throw result.error;
  return presentQueue(result.value);
};
const vbat = {
  point: { id: "EPS.VBAT", name: "VBAT", subsystem: "EPS", unit: "V" },
  condition: "red_low",
};

describe("action queue (M6)", () => {
  it("expands small alarm groups into Engage rows and keeps big ones grouped", () => {
    const small = present([
      item({ id: "alarm:a", ...vbat, spacecraft: [member(312), member(47, { stale: true })] }),
    ]);
    expect(small.map((r) => [r.title, r.action.label, r.meta])).toEqual([
      ["EARENDIL-312 · VBAT below red limit", "Engage", null],
      ["EARENDIL-047 · VBAT below red limit", "Engage", "LAST KNOWN · TELEMETRY STALE"],
    ]);
    const owned = present([
      item({
        id: "alarm:c",
        ...vbat,
        acknowledged: 1,
        spacecraft: [
          member(9, {
            status: "acknowledged",
            acknowledged_by: { kind: "user", id: "u1", name: "Mira K." },
            assignee: { id: "u2", name: "Tomás R." },
          }),
        ],
      }),
    ]);
    expect(owned[0]?.meta).toBe("ACK MIRA K. · → TOMÁS R.");
    expect(owned[0]?.action.label).toBe("Open");
    expect(owned[0]?.acknowledged).toBe(true);
    expect(
      present([
        item({
          id: "alarm:d",
          ...vbat,
          acknowledged: 2,
          spacecraft: [member(1), member(2), member(3)],
        }),
      ])[0]?.meta,
    ).toBe("2 OF 3 ACKNOWLEDGED");
    const big = present([
      item({ id: "alarm:b", ...vbat, spacecraft: [member(1), member(2), member(3)] }),
    ]);
    expect(big).toHaveLength(1);
    expect(big[0]).toMatchObject({
      title: "3 spacecraft · VBAT below red limit",
      sentence: "EARENDIL-001, EARENDIL-002, EARENDIL-003",
    });
    expect(big[0]?.action.to).toEqual({ name: "ops.alarms", query: { point: "EPS.VBAT" } });
  });

  it("keeps server order and maps every kind", () => {
    const rows = present([
      item({
        id: "c",
        kind: "command_failed",
        command: { id: "c1", name: "SET_POWER_MODE" },
        outcome: "failed",
        spacecraft: [member(9)],
      }),
      item({
        id: "a",
        priority: 2,
        kind: "approval",
        state: "caution",
        command_requests: [
          {
            id: "r",
            command_name: "HEATER_SET",
            target: { id: "t", name: "EARENDIL-140" },
            requested_by: "Ana P.",
            status: "approval_pending",
          },
        ],
      }),
      item({
        id: "s",
        priority: 2,
        kind: "stale",
        state: "stale",
        plane: 3,
        spacecraft: [member(72)],
      }),
      item({ id: "l", priority: 3, kind: "limits_not_configured", state: "off" }),
    ]);
    expect(rows.map((r) => r.title)).toEqual([
      "SET_POWER_MODE failed · 1 spacecraft",
      "1 command request awaits your GO",
      "1 in plane 3 stale",
      "Ground limits not configured",
    ]);
    expect(rows[1]?.sentence).toBe("HEATER_SET · EARENDIL-140 · by Ana P.");
  });

  it("rejects an unknown priority (an unknown kind only drops its row: lead, #71)", () => {
    expect(decode(actionQueueReader, body([item({ priority: 4 })])).ok).toBe(false);
  });
});

describe("flight_event rows (02cdde37)", () => {
  it("read like alarm rows, worded as the state entered", () => {
    const [row] = present([
      item({
        id: "flight_event:x",
        kind: "flight_event",
        source: "catalog_monitoring",
        point: { id: "HK.MODE", name: "MODE", subsystem: "HK", unit: null },
        spacecraft: [member(4)],
        event: { value_json: '"SAFE"', entered_at: "2026-11-10T03:12:00Z" },
      }),
    ]);
    expect(row?.title).toBe("EARENDIL-004 · MODE is SAFE");
  });
});

describe("approval rows (backlog §2)", () => {
  const group = (id: string) => ({
    id,
    title: `NOOP ${id}`,
    member_count: 10,
    target_count: 10,
    requested_by: "QA Operator",
    requested_at: "2026-11-09T20:00:00Z",
  });
  it("one group opens its review; several open the GO queue", () => {
    const [one] = present([
      item({
        id: "approval",
        kind: "approval",
        priority: 2,
        state: "caution",
        command_groups: [group("g1")],
      }),
    ]);
    expect(one?.title).toBe("1 command request awaits your GO");
    expect(one?.sentence).toBe("NOOP g1 · 10 targets · by QA Operator");
    expect(one?.action.to).toEqual({
      name: "ops.commands.request",
      params: { requestId: "g1", view: "review" },
    });
    const [two] = present([
      item({
        id: "approval",
        kind: "approval",
        priority: 2,
        state: "caution",
        command_groups: [group("g1"), group("g2")],
      }),
    ]);
    expect(two?.action.to).toEqual({ name: "ops.commands", query: { awaiting: "me" } });
  });
});

describe("attention rows (U31, fafe581a)", () => {
  const attention = (overrides: Record<string, unknown> = {}) =>
    item({
      id: "attention:pass_resolution:at-1",
      priority: 2,
      kind: "attention",
      state: "caution",
      source: "pass_resolution",
      since: "2026-11-09T10:55:00Z",
      due_at: "2026-11-09T20:12:00Z",
      spacecraft: [
        member(1, {
          violating_points: null,
          value: null,
          first_crossed_at: null,
        }),
      ],
      attention: {
        id: "at-1",
        source: "pass_resolution",
        conflict: "contradicts_attestation",
        state: "open",
        acknowledged_by: null,
        contact_id: "contact-9",
        reservation_id: "pass-9",
        station: { ref: "svb-1", id: "st-1", code: "SVB-1", name: "Svalbard 1" },
        provider: { id: "p-1", name: "Northlight" },
        starts_at: "2026-11-09T20:12:00Z",
        raised_at: "2026-11-09T10:55:00Z",
        provider_message: null,
        resolution: {
          action: "attested_booked",
          actor: { kind: "user", id: "u-1", name: "Mira K." },
          at: "2026-11-09T10:52:00Z",
          note: null,
          provider_reference: "NL-48213",
        },
        ...overrides,
      },
    });

  it("reads in U31 copy and reviews the contact", () => {
    const [row] = present([attention()]);
    expect(row?.title).toBe("EARENDIL-001 · Northlight says a pass marked booked isn't.");
    expect(row?.sentence).toBe(
      "Marked booked by Mira K. 10:52Z with ref NL-48213. Don't count on this contact.",
    );
    expect(row?.meta).toBe("SVB-1");
    expect(row?.due).toEqual({ label: "AOS", at: "2026-11-09T20:12:00Z" });
    expect(row?.action).toEqual({
      label: "Review",
      to: { name: "ops.contacts", query: { contact: "pass-9" } },
    });
  });

  it("cancel_failed quotes the provider without doubling the stop; ack marks the row", () => {
    const [row] = present([
      attention({
        conflict: "cancel_failed",
        provider_message: "Window locked.",
        state: "acknowledged",
        acknowledged_by: { kind: "user", id: "u-2", name: "Sam T." },
      }),
    ]);
    expect(row?.sentence).toBe("Window locked. The pass may still be booked and billed.");
    expect(row?.meta).toBe("SVB-1 · ACK SAM T.");
    expect(row?.acknowledged).toBe(true);
  });

  it("a resolved row fades in place for 5 s", () => {
    const before = present([item({ id: "setup:a", kind: "setup", priority: 3 }), attention()]);
    const after = present([item({ id: "setup:a", kind: "setup", priority: 3 })]);
    const resolved = [
      {
        id: "attention:pass_resolution:at-1",
        resolved_by: { kind: "user", id: "u-1", name: "Mira K." },
        action: "resolved",
        resolved_at: "2026-11-09T11:00:00Z",
      },
    ];
    const fading = newlyResolved(before, after, resolved, [], 1_000);
    expect(fading.map((f) => [f.index, f.until, f.item.sentence, f.item.state])).toEqual([
      [1, 6_000, "Resolved by Mira K.", "off"],
    ]);
    expect(withFading(after, fading).map((r) => r.key)).toEqual([
      "setup:a",
      "attention:pass_resolution:at-1|resolved",
    ]);
    expect(newlyResolved(before, after, resolved, fading, 2_000)).toEqual([]);
  });

  it("uplink_blocked (U33): same envelope, nulls where it has no conflict", () => {
    const [row] = present(
      [
        attention({
          conflict: null,
          provider_message: null,
          resolution: null,
          acknowledged_by: null,
          uplink: {
            state: "blocked",
            reason: "protocol_state_restore_required",
            since: "2026-11-09T20:00:00Z",
            command_group_ids: ["g1", "g2"],
          },
        }),
      ].map((i) => ({ ...i, source: "uplink_blocked", priority: 1, state: "critical" })),
    );
    expect(row?.title).toBe("EARENDIL-001 · Can't command on the SVB-1 pass.");
    expect(row?.sentence).toBe(
      "The uplink restarted after this pass had sent commands, and it can't resume. 2 command groups are queued for it.",
    );
    expect(row?.acknowledged).toBe(false);
  });

  it("pass_release reads the release outcome", () => {
    const [row] = present(
      [
        attention({
          conflict: "cancel_failed",
          resolution: null,
          provider_message: null,
          release: { outcome: "refused", reason: "Window locked." },
        }),
      ].map((i) => ({ ...i, source: "pass_release" })),
    );
    expect(row?.title).toBe("EARENDIL-001 · Release not confirmed: Northlight refused the cancel.");
    expect(row?.sentence).toBe("Window locked. The pass may still be booked and billed.");
  });

  it("says what closed it, never 'by Cadence'", () => {
    const r = (kind: string, name: string | null, action: string | null) => ({
      id: "x",
      resolved_by: { kind, id: null, name },
      action,
      resolved_at: "2026-11-09T11:00:00Z",
    });
    expect(resolvedWords(r("provider", "Northlight", "confirmed"))).toBe(
      "Resolved: Northlight confirmed.",
    );
    expect(resolvedWords(r("system", "Cadence", "cancel_confirmed"))).toBe(
      "Resolved: cancel confirmed.",
    );
    expect(resolvedWords(r("user", "Mira K.", "resolved"))).toBe("Resolved by Mira K.");
  });
});

describe("queue sources (ops.md b7008dd6, U35)", () => {
  const svb = {
    ref: "earendil-svalbard",
    id: "earendil-svalbard",
    code: "SVB-1",
    name: "Svalbard",
  };
  const missed = (scid: number, next: boolean, priority: 1 | 2) =>
    item({
      id: `missed_pass:sc-${scid}`,
      kind: "missed_pass",
      priority,
      state: priority === 1 ? "critical" : "caution",
      spacecraft: [member(scid, { violating_points: null, value: null, first_crossed_at: null })],
      missed_passes: [
        {
          reservation_id: `r-${scid}`,
          station: svb,
          planned_aos: "2026-11-10T02:21:00Z",
          outcome: "missed",
          cause: "Antenna fault",
          owner: "provider",
        },
      ],
      next_contact: next
        ? {
            reservation_id: `n-${scid}`,
            station: { ...svb, code: "KIR" },
            aos: "2026-11-10T04:00:00Z",
          }
        : null,
    });

  it("one or two misses stay per spacecraft", () => {
    const [row] = present([missed(4, false, 1)]);
    expect(row?.title).toBe("EARENDIL-004 · 1 missed pass at SVB-1 · antenna fault");
    expect(row?.sentence).toBe(
      "Missed at 02:21Z (the provider's side). No booked contact in the next 6 h.",
    );
    expect(row?.action.to).toEqual({ name: "ops.contacts.review", query: { day: "2026-11-10" } });
  });

  it("3+ sharing a station and cause group, taking the highest priority", () => {
    const rows = present([
      missed(4, false, 1),
      missed(11, true, 2),
      missed(19, true, 2),
      missed(23, false, 1),
    ]);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.priority).toBe(1);
    expect(rows[0]?.title).toBe("4 missed passes at SVB-1 · antenna fault");
    expect(rows[0]?.sentence).toBe(
      "EARENDIL-004, -011, -019 and 1 more · 2 have no contact in the next 6 h",
    );
  });

  it("a station issue reads its window and re-plans that station", () => {
    const [row] = present([
      item({
        id: "station:earendil-svalbard",
        kind: "station",
        priority: 2,
        state: "caution",
        station_issue: {
          station: svb,
          window: {
            id: "w1",
            kind: "outage",
            starts_at: "2026-11-10T03:00:00Z",
            ends_at: null,
            source: "provider",
          },
          affected: [
            { reservation_id: "a", spacecraft_id: "sc-4", aos: "2026-11-10T03:30:00Z" },
            { reservation_id: "b", spacecraft_id: "sc-5", aos: "2026-11-10T03:10:00Z" },
          ],
        },
      }),
    ]);
    expect(row?.title).toBe("SVB-1 · outage overlaps 2 booked passes");
    expect(row?.sentence).toBe("Outage from 03:00Z · no end reported (provider).");
    expect(row?.due).toEqual({ label: "AOS", at: "2026-11-10T03:10:00Z" });
    expect(row?.action.to).toEqual({
      name: "ops.contacts.replan.station",
      params: { stationId: "earendil-svalbard" },
    });
  });
});

describe("contact_settlement (U37, #71)", () => {
  // domain's sample item, verbatim apart from refs.
  const sample = {
    id: "realized_contact_ab12",
    source: "contact_settlement",
    conflict: "unsettled",
    state: "open",
    reason: "settle_deadline",
    failure_kind: "telemetry_storage_unavailable",
    failure_message: "telemetry storage unreachable (connection refused)",
    spacecraft_id: "spacecraft-earendil-001",
    contact_id: "scheduled_contact_cd34",
    realized_contact_id: "realized_contact_ab12",
    ground_station_ref: "svb",
    provider_id: "p-1",
    station: { ref: "svb", id: "st-1", code: "SVA", name: "Svalbard" },
    provider: { id: "p-1", name: "Northlight" },
    starts_at: "2026-11-11T18:49:00Z",
    ends_at: "2026-11-11T18:57:00Z",
    raised_at: "2026-11-12T00:57:00Z",
    deadline_at: "2026-11-12T00:57:00Z",
    backlog: { entries: 1204, bytes: 3355443, journals: 1 },
    expires_at: null,
    retry: "automatic",
    next_attempt_at: null,
    acknowledged_by: null,
    provider_message: null,
    resolution: null,
  };
  const settlement = (overrides: Record<string, unknown> = {}) =>
    item({
      id: "attention:contact_settlement:realized_contact_ab12",
      priority: 2,
      kind: "attention",
      state: "caution",
      source: "contact_settlement",
      spacecraft: [member(1, { violating_points: null, value: null, first_crossed_at: null })],
      attention: { ...sample, ...overrides },
    });
  const today = new Date("2026-11-11T22:00:00Z");
  const read = (o: Record<string, unknown> = {}) => {
    const r = decode(attentionReader, { ...sample, ...o });
    if (!r.ok) throw new Error(r.error.message);
    return r.value;
  };

  it("reads domain's sample and words it per U37", () => {
    const a = read();
    expect(attentionWords(a, today)).toEqual({
      what: "Telemetry from the SVA 18:49Z pass isn't stored yet.",
      evidence:
        "1,204 entries (3.4 MB) are on disk. Telemetry storage is unavailable; Cadence stores them when it's back.",
    });
    expect(attentionMeta(a, today)).toBe("SVA · NORTHLIGHT · 18:49Z–18:57Z");
    expect(attentionWords(a, new Date("2026-11-12T01:00:00Z")).what).toBe(
      "Telemetry from the SVA 11-11 18:49Z pass isn't stored yet.",
    );
  });

  it("evidence by failure_kind; the outage's own message stays out", () => {
    expect(
      attentionWords(read({ failure_kind: "settle_failed", failure_message: "disk full." }), today)
        .evidence,
    ).toBe("1,204 entries (3.4 MB) are on disk. Cadence couldn't store them: disk full.");
    expect(
      attentionWords(read({ failure_kind: null, failure_message: null }), today).evidence,
    ).toBe("1,204 entries (3.4 MB) are on disk, past the 00:57Z deadline for storing them.");
    expect(
      attentionWords(read({ station: { ref: null, id: null, code: null, name: null } }), today)
        .what,
    ).toBe("Telemetry from the 18:49Z pass isn't stored yet.");
  });

  it("is a Review row with no AOS countdown; resolves as 'telemetry stored'", () => {
    const [row] = present([settlement()]);
    expect(row?.due).toBeUndefined();
    expect(row?.action).toEqual({
      label: "Review",
      to: { name: "ops.contacts", query: { contact: "scheduled_contact_cd34" } },
    });
    expect(
      resolvedWords({
        id: "x",
        resolved_by: { kind: "system", id: null, name: null },
        action: "replayed",
        resolved_at: "2026-11-12T01:00:00Z",
      }),
    ).toBe("Resolved: telemetry stored.");
  });

  it("folds two or more of one failure_kind into a Show all row (U37)", () => {
    const two = (id: string, starts: string, extra: Record<string, unknown> = {}) => ({
      ...settlement({ id, starts_at: starts, ...extra }),
      id: `attention:contact_settlement:${id}`,
    });
    const rows = present([
      two("a", "2026-11-11T18:49:00Z"),
      item({ id: "setup:a", kind: "setup", priority: 3 }),
      two("b", "2026-11-11T06:01:00Z"),
      two("c", "2026-11-11T07:00:00Z", { failure_kind: "settle_failed" }),
    ]);
    expect(rows.map((r) => r.key)).toEqual([
      "settlement:telemetry_storage_unavailable",
      "setup:a",
      "attention:contact_settlement:c",
    ]);
    const [fold] = rows;
    expect(fold?.title).toBe("Telemetry from 2 passes isn't stored yet.");
    expect(fold?.sentence).toBe(
      "2,408 entries (6.7 MB) are on disk. Telemetry storage is unavailable; Cadence stores them when it's back.",
    );
    expect(fold?.action.label).toBe("Show all 2");
    expect(fold?.list?.rows.map((r) => r.key)).toEqual([
      "attention:contact_settlement:b",
      "attention:contact_settlement:a",
    ]);
    // It fades only when its last member resolves.
    const done = (id: string) => ({
      id: `attention:contact_settlement:${id}`,
      resolved_by: { kind: "system", id: null, name: null },
      action: "replayed",
      resolved_at: "2026-11-12T01:00:00Z",
    });
    const one = present([two("a", "2026-11-11T18:49:00Z")]);
    expect(newlyResolved(rows, one, [done("b")], [], 0)).toEqual([]);
    const fading = newlyResolved(one, [], [done("a")], [], 0);
    expect(fading.map((f) => [f.item.key, f.item.sentence])).toEqual([
      ["attention:contact_settlement:a|resolved", "Resolved: telemetry stored."],
    ]);
    expect(
      newlyResolved(rows, [], [done("a"), done("b")], [], 0).filter((f) =>
        f.item.key.startsWith("settlement:"),
      ),
    ).toHaveLength(1);
  });

  it("an unknown kind or source drops one row, not the whole read", () => {
    const r = decode(actionQueueReader, {
      observed_at: "2026-11-11T22:00:00Z",
      counts: { p1: 0, p2: 2, p3: 0, spacecraft_p1: 0 },
      items: [
        item({ id: "future:1", kind: "something_new", source: "brand_new_source", priority: 2 }),
        item({ id: "setup:a", kind: "setup", priority: 3, source: "brand_new_source" }),
      ],
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(presentQueue(r.value).map((q) => q.key)).toEqual(["setup:a"]);
  });
});
