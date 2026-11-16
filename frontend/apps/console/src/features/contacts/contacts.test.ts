import { findingKinds, findingTitle, findingsMeta, type Finding } from "./findings.ts";
import { contactTrail } from "./trail.ts";
import { duration, findingRows } from "./findingRows.ts";
import type { Availability, AvailabilityWindow } from "@/features/scheduling/index.ts";
import { releaseErrorWords } from "./release.ts";
import { describe, expect, it } from "vite-plus/test";
import {
  stationId as stationIdReader,
  spacecraftId as spacecraftIdReader,
  scid as scidReader,
  decode,
  type ApiError,
} from "@/api/index.ts";
import { passesReader, type Pass } from "./api.ts";
import { availabilityBands, passGantt, passStatus } from "./gantt.ts";
import { attentionReader, type Attention } from "@/features/now/index.ts";
import { attentionErrorWords, resolutionRecord, whatToDo } from "./attention.ts";
import {
  droppedLine,
  noRecoverText,
  groupBlockedLine,
  groupUplinkReader,
  passReadinessReader,
  readinessReasons,
  readinessTag,
  recoverable,
  recoverErrorWords,
  type ReadinessReason,
} from "./readiness.ts";

/** Typing §12: readiness fixtures go through the real readers, so strings become the unions. */
const readRaw = <T>(reader: (v: unknown, path?: string) => T, raw: unknown): T => {
  const r = decode(reader, raw);
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const reason = (key: string): ReadinessReason =>
  (readinessReasons as readonly string[]).includes(key)
    ? (key as ReadinessReason)
    : { unrecognized: key };

const now = Date.parse("2026-11-09T02:00:00Z");
const pass = (id: string, overrides: Partial<Pass> = {}): Pass => ({
  id,
  kind: "contact",
  booked: undefined,
  scheduled_contact_id: undefined,
  state: "confirmed",
  pass_phase: "scheduled",
  delivery_state: "pending",
  spacecraft_id: spacecraftIdReader("sc-312"),
  spacecraft: { id: "sc-312", name: "EARENDIL-312", scid: scidReader(312) },
  station: { ref: "SVL", id: "gs-svl", code: "SVB", name: "Svalbard" },
  antenna: null,
  starts_at: "2026-11-09T02:30:00Z",
  ends_at: "2026-11-09T02:38:00Z",
  uplink_capable: null,
  source: { provider: "p", provider_name: "Simulator", synthetic: true },
  max_elevation_deg: null,
  plan: null,
  requirement: undefined,
  ended_by: null,
  replaced_by: null,
  booking_evidence: null,
  attested_by: null,
  uplink_confirmed: null,
  attention: null,
  attentions: undefined,
  uplink_readiness: null,
  provider_revision: null,
  releasable: undefined,
  off_plan: undefined,
  provider_changes: undefined,
  contact_action: undefined,
  contact_ended: undefined,
  incomplete_at_end: undefined,
  window_moves: undefined,
  telemetry_stored: undefined,
  ...overrides,
});

describe("passes", () => {
  it("decodes the read and rejects unknown states", () => {
    const body = {
      from: "2026-11-09T02:00:00Z",
      to: "2026-11-09T04:00:00Z",
      truncated: false,
      passes: [
        pass("a"),
        pass("b", { plan: { id: "contact_plan_1", version: 42, day: undefined } }),
      ],
    };
    expect(decode(passesReader, body).ok).toBe(true);
    expect(decode(passesReader, { ...body, passes: [{ ...pass("a"), state: "maybe" }] }).ok).toBe(
      false,
    );
  });

  it("reads status from state, phase and time", () => {
    expect(passStatus(pass("a"), now)).toBe("scheduled");
    expect(passStatus(pass("b", { state: "active" }), now)).toBe("live");
    expect(passStatus(pass("c", { pass_phase: "pass" }), now)).toBe("live");
    expect(passStatus(pass("d", { ends_at: "2026-11-09T01:50:00Z" }), now)).toBe("done");
    expect(
      passGantt([pass("d", { ends_at: "2026-11-09T01:50:00Z" })], () => null, now).bars[0]?.kind,
    ).toBe("done");
    expect(passStatus(pass("e", { state: "rejected" }), now)).toBe("problem");
    expect(passStatus(pass("f", { state: "canceled" }), now)).toBe("canceled");
  });

  it("maps to station rows and spacecraft-numbered bars, skipping canceled", () => {
    const { rows, bars } = passGantt(
      [
        pass("a"),
        pass("b", { station: { ref: "XYZ", id: null, code: null, name: null } }),
        pass("c", { state: "canceled" }),
      ],
      () => ({ name: "EARENDIL-312", scid: scidReader(312) }),
      now,
    );
    expect(rows.map((r) => r.label)).toEqual(["SVB", "XYZ"]);
    expect(bars.map((b) => [b.label, b.kind])).toEqual([
      ["312", "scheduled"],
      ["312", "scheduled"],
    ]);
    expect(bars[0]?.description).toBe("EARENDIL-312 at Svalbard, scheduled (synthetic window)");
    // Without a fleet match, the row's own identity names it.
    // D3 chips: a match dims the rest in place; queued uplinks notch their bar.
    const marked = passGantt([pass("a"), pass("b")], () => null, now, null, "station", {
      match: (p) => p.id === "a",
      uplinks: new Set(["b"]),
    }).bars;
    expect(marked.map((b) => [b.id, b.dim ?? false, b.notch ?? false])).toEqual([
      ["a", false, false],
      ["b", true, true],
    ]);
    expect(marked[1]?.description).toMatch(/uplink queued$/);
    const own = passGantt([pass("x")], () => null, now, null, "spacecraft");
    expect(own.rows[0]?.label).toBe("EARENDIL-312");
  });
});

describe("attention block words (U32)", () => {
  const item = (overrides: Partial<Attention> = {}): Attention => ({
    id: "at-1",
    source: "pass_resolution",
    conflict: "contradicts_attestation",
    state: "open",
    acknowledged_by: null,
    contact_id: null,
    reservation_id: "pass-9",
    uplink: null,
    release: null,
    backlog: undefined,
    ends_at: undefined,
    deadline_at: undefined,
    failure_kind: undefined,
    failure_message: undefined,
    retry: undefined,
    journal: undefined,
    reason: undefined,
    desired_generation: undefined,
    applied_generation: undefined,
    since: undefined,
    change_set_id: undefined,
    activated_at: undefined,
    attempts: undefined,
    next_attempt_at: undefined,
    last_attempt_at: undefined,
    activation_request_id: undefined,
    error_code: undefined,
    error: undefined,
    summary: undefined,
    kind: undefined,
    app: undefined,
    spacecraft_ids: undefined,
    spacecraft_count: undefined,
    retryable: undefined,
    approved_by: undefined,
    approved_at: undefined,
    runtime_not_applied: undefined,
    provider_change: undefined,
    realized_contact_id: undefined,
    provider_profile_id: undefined,
    provider_profile_name: undefined,
    holder: undefined,
    listen_port: undefined,
    transport_id: undefined,
    transport_name: undefined,
    contact_label: undefined,
    transport: undefined,
    journal_usage: undefined,
    drops: undefined,
    diagnostics: undefined,
    counts: undefined,
    stored_without_archive: undefined,
    first_received_at: undefined,
    last_received_at: undefined,
    last_seen_at: undefined,
    actions: undefined,
    last_retry: undefined,
    refused_count: undefined,
    last_refused_at: undefined,
    last_refusal: undefined,
    connected: undefined,
    own_quiet_since: undefined,
    job: undefined,
    words: undefined,
    started_at: undefined,
    found_at: undefined,
    day: undefined,
    first_window_at: undefined,
    group: undefined,
    target_count: undefined,
    sent: undefined,
    total: undefined,
    expired_at: undefined,
    journal_disk: undefined,
    due_at: undefined,
    severity: undefined,
    requirements_count: undefined,
    open_requirements_count: undefined,
    plan: undefined,
    approvers: undefined,
    viewer_can_approve: undefined,
    viewer_can_book: undefined,
    shared_with: undefined,
    ground_station_ref: undefined,
    station: { ref: "svb-1", id: "st-1", code: "SVB-1", name: "Svalbard 1" },
    provider: { id: "p-1", name: "Northlight" },
    starts_at: "2026-11-14T03:00:00Z",
    raised_at: "2026-11-09T10:55:00Z",
    provider_message: null,
    resolution: {
      action: { unrecognized: "attested_booked" },
      actor: { kind: "user", id: "u-1", name: "Mira K." },
      at: "2026-11-09T10:52:00Z",
      note: "Called the Northlight ops desk.",
      provider_reference: "NL-48213",
    },
    ...overrides,
  });

  it("reads the resolution record", () => {
    expect(resolutionRecord(item())).toBe(
      "Marked booked by Mira K. 10:52Z · ref NL-48213 · ‘Called the Northlight ops desk.’",
    );
    const notBooked = item({
      conflict: "late_confirmation",
      resolution: {
        action: { unrecognized: "marked_not_booked" },
        actor: { kind: "user", id: "u-1", name: "Mira K." },
        at: "2026-11-09T10:52:00Z",
        note: null,
        provider_reference: null,
      },
    });
    expect(resolutionRecord(notBooked)).toBe("Marked not booked by Mira K. 10:52Z");
  });

  it("says what to do per conflict, linking the plan only when re-planning helps", () => {
    expect(whatToDo(item())).toEqual({
      text: "Don't count on this contact. Re-plan the spacecraft if it needs this contact.",
      plan: true,
    });
    expect(whatToDo(item({ conflict: "cancel_failed" })).text).toBe(
      "Check with Northlight that the pass is canceled. If it can't be, keep it and record what you did.",
    );
  });

  it("an already-resolved item says so and refreshes", () => {
    expect(
      attentionErrorWords({
        kind: "conflict",
        code: "attention_item_not_open",
        message: "not open",
        details: undefined,
      }),
    ).toEqual({ text: "This was already resolved.", refresh: true });
  });
});

describe("uplink readiness (U33)", () => {
  it("is quiet when ready except in the drawer; blocked is crit with queued groups", () => {
    const r = (state: string, extra = {}) =>
      readRaw(passReadinessReader, {
        state,
        reason: null,
        since: null,
        command_groups_queued: 0,
        ...extra,
      });
    expect(readinessTag(r("ready"), "row")).toBeNull();
    expect(readinessTag(r("ready"), "drawer")?.label).toBe("Uplink ready");
    expect(readinessTag(r("recovering", { since: "2026-11-10T00:41:00Z" }), "row")).toEqual({
      state: "neutral",
      label: "Uplink qualifying…",
      sentence: "Qualifying since 00:41Z.",
    });
    const blocked = r("blocked", {
      reason: "protocol_state_restore_required",
      command_groups_queued: 2,
    });
    expect(readinessTag(blocked, "row", { los: "2026-11-10T01:06:00Z" })).toEqual({
      state: "crit",
      label: "Can't command",
      sentence:
        "Can't command: the uplink restarted after this pass had sent commands, and it can't resume before LOS 01:06Z. The next pass isn't affected.",
    });
    expect(
      readinessTag({ ...blocked, command_groups_queued: 0, reason: reason("lane_held") }, "row"),
    ).toEqual({
      state: "caution",
      label: "Can't command",
      sentence: "Can't command: the provider returned an error (Lane held).",
    });
  });

  it("words a blocked group's line, naming the next pass and expiry only when known", () => {
    const station = { ref: null, id: null, code: "SVB-1", name: null };
    const uplink = readRaw(groupUplinkReader, {
      pass: { reservation_id: "p1", contact_id: null, station, starts_at: "2026-11-10T00:54:00Z" },
      next_pass: {
        reservation_id: "p2",
        contact_id: null,
        station: { ...station, code: "FBK" },
        starts_at: "2026-11-10T02:31:00Z",
      },
      readiness: { state: "blocked", reason: "protocol_state_restore_required", since: null },
    });
    const readiness = uplink.readiness ?? { state: "blocked" as const, reason: null, since: null };
    expect(groupBlockedLine(uplink, "2026-11-10T03:00:00Z")).toBe(
      "Can't command on the SVB-1 pass (AOS 00:54Z): the uplink restarted after this pass had sent commands, and it can't resume. Nothing will be sent on this pass. It goes on the next pass (FBK 02:31Z) unless it expires at 03:00Z.",
    );
    const evidence = { ...readiness, reason: reason("attestation_expired") };
    expect(groupBlockedLine({ ...uplink, next_pass: null, readiness: evidence }, null)).toMatch(
      /until the uplink recovers\. No later pass is booked for it yet\.$/,
    );
    expect(
      groupBlockedLine({ ...uplink, readiness: { ...readiness, state: "ready" } }, null),
    ).toBeNull();
  });

  it("cop1_awaiting_clcw is qualifying, not blocked; a mid-pass restart can't be recovered", () => {
    expect(
      readinessTag(
        readRaw(passReadinessReader, {
          state: "qualifying",
          reason: "cop1_awaiting_clcw",
          since: null,
          command_groups_queued: 1,
        }),
        "row",
      ),
    ).toEqual({
      state: "neutral",
      label: "Uplink qualifying…",
      sentence: "Waiting for the spacecraft's first link report.",
    });
    expect(recoverable("protocol_state_restore_required")).toBe(false);
    expect(recoverable("provider_cannot_attest_uplink_sessions")).toBe(false);
    expect(recoverable(reason("attestation_signature"))).toBe(true);
  });

  it("words reasons per U33 amendment 2, naming the provider", () => {
    const c = { provider: "Northlight" };
    const tag = (key: string, state = "blocked") =>
      readinessTag(
        readRaw(passReadinessReader, { state, reason: key, since: null, command_groups_queued: 1 }),
        "row",
        c,
      )?.sentence;
    expect(tag("attestation_peer")).toBe(
      "Can't command: Northlight's proof for this session didn't check out.",
    );
    expect(tag("session_not_attached", "qualifying")).toBe(
      "Waiting for Northlight's uplink connection.",
    );
    expect(tag("weird_thing")).toBe("Can't command: Northlight returned an error (Weird thing).");
    expect(tag("unverified_peer_connected")).toBe(
      "Can't command: an unverified connection took the uplink, so Cadence dropped it and is waiting for Northlight's verified one.",
    );
    expect(recoverable("unverified_peer_connected")).toBe(true);
    expect(tag("cop1_no_clcw_report")).toBe(
      "Can't command: the spacecraft didn't send a link report within 15 s of the uplink connecting. It clears when the spacecraft reports or the link reconnects.",
    );
    expect(recoverable("cop1_no_clcw_report")).toBe(false);
    expect(tag("cop1_clcw_stale", "qualifying")).toBe(
      "The spacecraft's link reports stopped; waiting for them to resume.",
    );
  });

  it("names the next pass by station code from the index when the row lacks it", () => {
    const station = { ref: "earendil-kiruna", id: null, code: null, name: null };
    const uplink = readRaw(groupUplinkReader, {
      pass: { reservation_id: "p1", contact_id: null, station, starts_at: "2026-11-10T00:54:00Z" },
      next_pass: {
        reservation_id: "p2",
        contact_id: null,
        station,
        starts_at: "2026-11-10T02:31:00Z",
      },
      readiness: { state: "blocked", reason: "attestation_peer", since: null },
    });
    const kiruna = (key: string | null | undefined) =>
      key === "earendil-kiruna" ? { code: "KIR", provider: "Northlight" } : null;
    const stations = { byId: kiruna, byRef: kiruna };
    expect(groupBlockedLine(uplink, null, stations)).toContain(
      "(AOS 00:54Z): Northlight's proof for this session didn't check out.",
    );
    expect(groupBlockedLine(uplink, null, stations)).toMatch(
      /Otherwise it goes on the next pass \(KIR 02:31Z\)\.$/,
    );
    expect(groupBlockedLine(uplink, null)).toMatch(
      /Otherwise it goes on the next pass at 02:31Z\.$/,
    );
  });

  it("words a refused recovery", () => {
    expect(
      recoverErrorWords({
        kind: "conflict",
        code: "uplink_recovery_refused",
        message: "refused",
        details: { reason: "provider_unreachable" },
      }),
    ).toEqual({
      tone: "caution",
      text: "Recovery refused: the provider returned an error (Provider unreachable).",
    });
  });
});

describe("D3 station bands (S7)", () => {
  it("draws uncleared windows on station rows that are shown", () => {
    const window = (over: Partial<AvailabilityWindow>): AvailabilityWindow => ({
      id: "w",
      ground_station_id: stationIdReader("gs-svl"),
      kind: "outage",
      from: "2026-11-09T02:00:00Z",
      to: "2026-11-09T03:00:00Z",
      eta: null,
      source: "provider",
      reported_at: null,
      reason: "Antenna fault",
      cleared_at: null,
      ...over,
    });
    const station = (
      id: string,
      windows: AvailabilityWindow[],
    ): Availability["stations"][number] => ({
      ground_station_id: stationIdReader(id),
      state: "down",
      since: null,
      eta: null,
      basis: null,
      windows,
    });
    const av: Availability = {
      at: "2026-11-09T02:00:00Z",
      stations: [
        station("gs-svl", [
          window({}),
          window({ to: null, kind: "maintenance", reason: null }),
          window({ cleared_at: "2026-11-09T02:10:00Z" }),
        ]),
        station("gs-other", [window({ ground_station_id: stationIdReader("gs-other") })]),
      ],
    };
    const bands = availabilityBands(av, [{ id: "gs-svl", label: "SVB" }], 99);
    expect(bands.map((b) => [b.rowId, b.kind, b.to, b.label])).toEqual([
      ["gs-svl", "outage", Date.parse("2026-11-09T03:00:00Z"), "Outage: Antenna fault"],
      ["gs-svl", "maintenance", 99, "Maintenance · no end reported"],
    ]);
  });
});

describe("D4 findings (M22)", () => {
  // Typing §12: kind is knownText; an unknown one keeps its raw word.
  const kindOf = (k: string): Finding["kind"] =>
    (findingKinds as readonly string[]).includes(k)
      ? (k as (typeof findingKinds)[number])
      : { unrecognized: k };
  const f = (kind: string, code: string | null, at: string | null): Finding => ({
    id: kind,
    kind: kindOf(kind),
    severity: "caution" as const,
    at,
    station: code ? { ref: null, id: null, code, name: null } : null,
    message: "m",
    passes: [],
    spacecraft: undefined,
    gap: undefined,
  });
  const gap = (n: number, from = "2026-11-13T00:04:34Z") => ({
    ...f("coverage_gap", null, from),
    id: `gap-${n}`,
    severity: "critical" as const,
    message: `EARENDIL-00${n} has no pass for 6h.`,
    spacecraft: { id: `sc-${n}`, name: `EARENDIL-00${n}`, scid: scidReader(n) },
    gap: { from, to: "2026-11-13T06:04:34Z", seconds: 21_600 },
  });
  it("folds same-cause coverage gaps into one row with its members (ux §7)", () => {
    const now = new Date("2026-11-13T00:04:40Z");
    const rows = findingRows(
      [gap(1), gap(2), f("station_double_booked", "SVB", null), gap(3)],
      now,
    );
    expect(rows.map((r) => [r.title, r.sentence, r.members?.length ?? null])).toEqual([
      ["Coverage gap 00:04Z", "3 spacecraft have no pass in the next 6 h.", 3],
      ["SVB double-booked", "m", null],
    ]);
    expect(rows[0]?.members?.[0]).toEqual({
      key: "gap-1",
      text: "EARENDIL-001",
      detail: "no pass 00:04Z–06:04Z",
      to: { name: "ops.spacecraft", params: { scId: 1, tab: "investigate" } },
    });
    const two = findingRows([gap(1), gap(2, "2026-11-13T03:00:00Z")], now);
    expect(two.map((r) => r.sentence)).toEqual([
      "EARENDIL-001 has no pass in the next 6 h.",
      "EARENDIL-002 has no pass for 6 h from 03:00Z.",
    ]);
    expect([duration(2_400), duration(5_400), duration(21_600)]).toEqual([
      "40 min",
      "1.5 h",
      "6 h",
    ]);
  });
  it("titles rows by station, kind and time", () => {
    expect(findingTitle(f("station_double_booked", "SVB", "2026-11-10T03:20:00Z"))).toBe(
      "SVB double-booked 03:20Z",
    );
    expect(findingTitle(f("coverage_gap", null, null))).toBe("Coverage gap");
  });
  it("header meta names only non-zero counts", () => {
    expect(
      findingsMeta({ truncated: false, counts: { conflicts: 2, gaps: 1 }, findings: [] }),
    ).toBe("2 conflicts · 1 coverage gap");
    expect(
      findingsMeta({ truncated: false, counts: { conflicts: 0, gaps: 0 }, findings: [] }),
    ).toBeNull();
  });
});

describe("D2 Release words (50c5e572, ux)", () => {
  it("refused and not-sent change nothing; unknown is unclear", () => {
    const e = (outcome: string) =>
      ({
        kind: "conflict",
        code: "provider_cancel_failed",
        message: "x",
        details: { outcome, reason: "Window locked.", state: "confirmed" },
      }) as const;
    expect(releaseErrorWords(e("refused"), "Northlight").text).toBe(
      "Nothing changed: Northlight refused the cancel (Window locked).",
    );
    expect(releaseErrorWords(e("not_sent"), "Northlight").text).toBe(
      "Nothing changed: the cancel wasn't sent (Window locked).",
    );
    // DECISIONS #78: a refused off-plan release names who may release it, as the caption does.
    const forbidden: ApiError = { kind: "forbidden", code: "forbidden", message: "No." };
    expect(releaseErrorWords(forbidden, "Northlight", "Mira K.").text).toBe(
      "Mira K. or an org admin can release this booking.",
    );
    expect(releaseErrorWords(forbidden, "Northlight").text).toBe(
      "Org admins can release a booking.",
    );
    expect(releaseErrorWords(e("unknown"), "Northlight")).toEqual({
      tone: "caution",
      text: "It's unclear whether Northlight canceled it (Window locked). The pass reads Unknown until Northlight answers.",
    });
  });
});

describe("D2 state trail (Contacts.md, ScheduleFlow M1)", () => {
  it("walks the path to where the contact is, marking only outcomes", () => {
    expect(contactTrail("in_contact")).toEqual([
      { label: "Requested" },
      { label: "Confirmed" },
      { label: "In contact" },
    ]);
    expect(contactTrail("rejected")).toEqual([
      { label: "Requested" },
      { label: "Rejected", outcome: "caution" },
    ]);
    expect(contactTrail("ended")).toContainEqual({ label: "Ended · not verified" });
  });
});

describe("U45 bar mark (lead bf3f36aac)", () => {
  const open = (source: string, conflict: string) =>
    readRaw(attentionReader, {
      id: `${source}-1`,
      source,
      conflict,
      state: "open",
      acknowledged_by: null,
      contact_id: "contact-1",
      station: null,
      provider: null,
      starts_at: null,
      raised_at: "2026-11-09T01:00:00Z",
      provider_message: null,
      resolution: null,
    });
  it("marks ◆ for a missed top item, ▲ for any other open one, nothing otherwise", () => {
    const missed = open("contact_start", "missed");
    const change = open("provider_change", "approval_required");
    const { bars } = passGantt(
      [
        pass("a", { attention: missed, attentions: [missed, change] }),
        pass("b", { attention: change, attentions: [change] }),
        pass("c"),
      ],
      () => null,
      now,
    );
    expect(bars.map((b) => [b.id, b.attention])).toEqual([
      ["a", "crit"],
      ["b", "caution"],
      ["c", undefined],
    ]);
    expect(bars[0]?.description).toContain(", was missed, and 1 more item");
  });
});

describe("U46 uplink dropped (api b9a60f096)", () => {
  const dropped = (queued: number | null, since: string | null = "2026-11-14T02:40:00Z") => ({
    state: "blocked" as const,
    reason: reason("uplink_leg_dropped"),
    since,
    command_groups_queued: queued,
  });
  it("tags the pass, crit only with groups queued, and says who dropped it and when", () => {
    expect(readinessTag(dropped(2), "drawer", { provider: "Northlight" })).toEqual({
      state: "crit",
      label: "Uplink dropped",
      sentence:
        "Northlight dropped the uplink from this pass at 02:40Z, so commands can't be sent on it.",
    });
    expect(readinessTag(dropped(0), "row")?.state).toBe("caution");
    expect(droppedLine(null, null)).toBe(
      "The provider dropped the uplink from this pass, so commands can't be sent on it.",
    );
  });
  it("offers no recovery and adds no second line", () => {
    expect(recoverable(reason("uplink_leg_dropped"))).toBe(false);
    expect(noRecoverText(reason("uplink_leg_dropped"))).toBeNull();
  });
});
