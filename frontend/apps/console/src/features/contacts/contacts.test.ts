import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { passesReader, type Pass } from "./api.ts";
import { passGantt, passStatus } from "./gantt.ts";
import type { Attention } from "@/features/now/index.ts";
import { attentionErrorWords, resolutionRecord, whatToDo } from "./attention.ts";
import { groupBlockedLine, readinessTag, recoverable, recoverErrorWords } from "./readiness.ts";

const now = Date.parse("2026-11-09T02:00:00Z");
const pass = (id: string, overrides: Partial<Pass> = {}): Pass => ({
  id,
  kind: "contact",
  state: "confirmed",
  pass_phase: "scheduled",
  delivery_state: "pending",
  spacecraft_id: "sc-312",
  spacecraft: { id: "sc-312", name: "EARENDIL-312", scid: 312 },
  station: { ref: "SVL", id: "gs-svl", code: "SVB", name: "Svalbard" },
  antenna: null,
  starts_at: "2026-11-09T02:30:00Z",
  ends_at: "2026-11-09T02:38:00Z",
  uplink_capable: null,
  source: { provider: "p", provider_name: "Simulator", synthetic: true },
  max_elevation_deg: null,
  plan: null,
  ended_by: null,
  replaced_by: null,
  booking_evidence: null,
  attested_by: null,
  uplink_confirmed: null,
  attention: null,
  uplink_readiness: null,
  ...overrides,
});

describe("passes", () => {
  it("decodes the read and rejects unknown states", () => {
    const body = {
      from: "2026-11-09T02:00:00Z",
      to: "2026-11-09T04:00:00Z",
      truncated: false,
      passes: [pass("a"), pass("b", { plan: { id: "contact_plan_1", version: 42 } })],
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
      () => ({ name: "EARENDIL-312", scid: 312 }),
      now,
    );
    expect(rows.map((r) => r.label)).toEqual(["SVB", "XYZ"]);
    expect(bars.map((b) => [b.label, b.kind])).toEqual([
      ["312", "scheduled"],
      ["312", "scheduled"],
    ]);
    expect(bars[0]?.description).toBe("EARENDIL-312 at Svalbard, scheduled (synthetic window)");
    // Without a fleet match, the row's own identity names it.
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
    station: { ref: "svb-1", id: "st-1", code: "SVB-1", name: "Svalbard 1" },
    provider: { id: "p-1", name: "Northlight" },
    starts_at: "2026-11-14T03:00:00Z",
    raised_at: "2026-11-09T10:55:00Z",
    provider_message: null,
    resolution: {
      action: "attested_booked",
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
        action: "marked_not_booked",
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
    const r = (state: string, extra = {}) => ({
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
      readinessTag({ ...blocked, command_groups_queued: 0, reason: "lane_held" }, "row"),
    ).toEqual({
      state: "caution",
      label: "Can't command",
      sentence: "Can't command: the provider returned an error (Lane held).",
    });
  });

  it("words a blocked group's line, naming the next pass and expiry only when known", () => {
    const station = { ref: null, id: null, code: "SVB-1", name: null };
    const uplink = {
      pass: { reservation_id: "p1", contact_id: null, station, starts_at: "2026-11-10T00:54:00Z" },
      next_pass: {
        reservation_id: "p2",
        contact_id: null,
        station: { ...station, code: "FBK" },
        starts_at: "2026-11-10T02:31:00Z",
      },
      readiness: { state: "blocked", reason: "protocol_state_restore_required", since: null },
    };
    expect(groupBlockedLine(uplink, "2026-11-10T03:00:00Z")).toBe(
      "Can't command on the SVB-1 pass (AOS 00:54Z): the uplink restarted after this pass had sent commands, and it can't resume. Nothing will be sent on this pass. It goes on the next pass (FBK 02:31Z) unless it expires at 03:00Z.",
    );
    const evidence = { ...uplink.readiness, reason: "attestation_expired" };
    expect(groupBlockedLine({ ...uplink, next_pass: null, readiness: evidence }, null)).toMatch(
      /until the uplink recovers\. No later pass is booked for it yet\.$/,
    );
    expect(
      groupBlockedLine({ ...uplink, readiness: { ...uplink.readiness, state: "ready" } }, null),
    ).toBeNull();
  });

  it("cop1_awaiting_clcw is qualifying, not blocked; a mid-pass restart can't be recovered", () => {
    expect(
      readinessTag(
        {
          state: "qualifying",
          reason: "cop1_awaiting_clcw",
          since: null,
          command_groups_queued: 1,
        },
        "row",
      ),
    ).toEqual({
      state: "neutral",
      label: "Uplink qualifying…",
      sentence: "Waiting for the spacecraft's first link report.",
    });
    expect(recoverable("protocol_state_restore_required")).toBe(false);
    expect(recoverable("provider_cannot_attest_uplink_sessions")).toBe(false);
    expect(recoverable("attestation_signature")).toBe(true);
  });

  it("words reasons per U33 amendment 2, naming the provider", () => {
    const c = { provider: "Northlight" };
    const tag = (reason: string, state = "blocked") =>
      readinessTag({ state, reason, since: null, command_groups_queued: 1 }, "row", c)?.sentence;
    expect(tag("attestation_peer")).toBe(
      "Can't command: Northlight's proof for this session didn't check out.",
    );
    expect(tag("session_not_attached", "qualifying")).toBe(
      "Waiting for Northlight's uplink connection.",
    );
    expect(tag("weird_thing")).toBe("Can't command: Northlight returned an error (Weird thing).");
  });

  it("names the next pass by station code from the index when the row lacks it", () => {
    const station = { ref: "earendil-kiruna", id: null, code: null, name: null };
    const uplink = {
      pass: { reservation_id: "p1", contact_id: null, station, starts_at: "2026-11-10T00:54:00Z" },
      next_pass: {
        reservation_id: "p2",
        contact_id: null,
        station,
        starts_at: "2026-11-10T02:31:00Z",
      },
      readiness: { state: "blocked", reason: "attestation_peer", since: null },
    };
    const codeOf = (ref: string | null | undefined) => (ref === "earendil-kiruna" ? "KIR" : null);
    expect(groupBlockedLine(uplink, null, codeOf)).toMatch(
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
