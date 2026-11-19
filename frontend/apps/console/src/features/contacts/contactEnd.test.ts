import { describe, expect, it } from "vite-plus/test";
import { decode, type ApiError } from "@/api/index.ts";
import { passReader } from "./api.ts";
import {
  commandsLine,
  consequenceLines,
  endedCode,
  endedLine,
  endedTag,
  refusalWords,
  sheetTitle,
} from "./contactEnd.ts";

const NOW = new Date("2026-11-14T12:50:00Z");

/** A pass row as api serves it, with U55's fields (decoded, as the screen reads it). */
const passOf = (o: Record<string, unknown> = {}) => {
  const r = decode(passReader, {
    id: "pass-7",
    kind: "contact",
    state: "confirmed",
    pass_phase: "scheduled",
    delivery_state: "pending",
    spacecraft_id: "spacecraft-earendil-007",
    spacecraft: { id: "spacecraft-earendil-007", name: "EARENDIL-007", scid: 7 },
    station: { ref: "puq", id: "gs-puq", code: "PUQ", name: "Punta Arenas" },
    antenna: null,
    starts_at: "2026-11-14T13:04:00Z",
    ends_at: "2026-11-14T13:12:00Z",
    uplink_capable: true,
    source: { provider: "p-1", provider_name: "Northlight", synthetic: false },
    max_elevation_deg: null,
    plan: null,
    ended_by: null,
    replaced_by: null,
    booking_evidence: null,
    attested_by: null,
    uplink_confirmed: null,
    attention: null,
    uplink_readiness: null,
    provider_revision: null,
    contact_action: "cancel",
    contact_ended: null,
    ...o,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const ended = (o: Record<string, unknown>) =>
  passOf({
    contact_action: null,
    contact_ended: {
      kind: "canceled",
      cause: "operator",
      by: { kind: "user", id: "u-1", name: "Mira K." },
      at: "2026-11-14T12:58:00Z",
      reason: "Its booking failed.",
      ...o,
    },
  }).contact_ended;
const conflict = (code: string, details: unknown): ApiError => ({
  kind: "conflict",
  code,
  message: "No.",
  details,
});
const queued = (
  count: number,
  exp: { count: number; earliest_at: string } | null,
  next = true,
) => ({
  count,
  expiring_before_next: exp,
  next_contact: next
    ? {
        station: { ref: "ksat", id: null, code: "KSAT", name: "KSAT" },
        starts_at: "2026-11-14T15:40:00Z",
      }
    : null,
});

describe("U55 cancel or end a contact", () => {
  it("titles the sheet and lists what stops, the booking and the commands", () => {
    const p = passOf();
    expect(sheetTitle("cancel", "EARENDIL-007", p, NOW)).toBe(
      "Cancel EARENDIL-007's PUQ 13:04Z contact?",
    );
    expect(sheetTitle("end", "EARENDIL-007", p, NOW)).toBe(
      "End EARENDIL-007's PUQ 13:04Z contact now?",
    );
    expect(consequenceLines("cancel", p, "EARENDIL-007", queued(2, null), true, NOW)).toEqual([
      "Cadence won't open this contact: nothing is received or sent on it.",
      "Northlight's booking isn't changed. If you don't want the pass either, release it after this.",
      "2 queued command requests wait for EARENDIL-007's next contact (KSAT 15:40Z).",
    ]);
    expect(consequenceLines("end", p, "EARENDIL-007", null, false, NOW)).toEqual([
      "Cadence stops receiving and sending now. Telemetry from the rest of this pass won't be received.",
      "Northlight's booking isn't changed: the provider may keep flying the pass until LOS 13:12Z.",
    ]);
  });

  it("words the commands line: none scheduled, and requests expiring before then", () => {
    expect(commandsLine("cancel", "EARENDIL-007", queued(2, null, false), NOW)).toBe(
      "2 queued command requests wait for EARENDIL-007's next contact; none is scheduled yet.",
    );
    expect(
      commandsLine(
        "end",
        "EARENDIL-007",
        queued(3, { count: 1, earliest_at: "2026-11-14T14:00:00Z" }),
        NOW,
      ),
    ).toBe(
      "Uplinks already sent stay sent. 3 queued requests wait for the next contact (KSAT 15:40Z). 1 of them expires at 14:00Z, before then.",
    );
    expect(
      commandsLine(
        "cancel",
        "EARENDIL-007",
        queued(1, { count: 1, earliest_at: "2026-11-14T14:00:00Z" }),
        NOW,
      ),
    ).toBe(
      "1 queued command request waits for EARENDIL-007's next contact (KSAT 15:40Z). It expires at 14:00Z, before then.",
    );
    expect(commandsLine("cancel", "EARENDIL-007", queued(0, null), NOW)).toBeNull();
  });

  it("history lines for an operator and for Cadence's own cancels; the tag", () => {
    const op = ended({});
    if (!op) throw new Error("ended");
    expect(endedLine(op, "Northlight", NOW)).toBe(
      "Canceled by Mira K. at 12:58Z: “Its booking failed.”",
    );
    expect(endedTag(op)).toEqual({ state: "off", label: "Canceled" });
    const early = ended({ kind: "ended_early", reason: null });
    if (!early) throw new Error("ended");
    expect(endedLine(early, "Northlight", NOW)).toBe("Ended early by Mira K. at 12:58Z.");
    expect(endedTag(early)?.label).toBe("Ended early");
    const sys = { by: { kind: "system", id: null, name: null } };
    const failed = ended({ ...sys, cause: "provider_failed", reason: "no antenna available" });
    const gone = ended({ ...sys, cause: "provider_canceled", reason: null });
    const odd = ended({ ...sys, cause: "provider_glitch", reason: "x" });
    if (!failed || !gone || !odd) throw new Error("ended");
    expect(endedLine(failed, "Northlight", NOW)).toBe(
      "Canceled by Cadence at 12:58Z: Northlight couldn't book this pass (“no antenna available”).",
    );
    expect(endedLine(gone, "Northlight", NOW)).toBe(
      "Canceled by Cadence at 12:58Z: Northlight canceled this pass.",
    );
    expect(endedLine(odd, "Northlight", NOW)).toBe("Canceled by Cadence at 12:58Z.");
    const bare = ended({ cause: null, by: null, at: null, reason: null });
    if (!bare) throw new Error("ended");
    expect(endedLine(bare, "Northlight", NOW)).toBe(
      "Canceled; when, who and why weren't recorded.",
    );
    const timed = ended({ cause: null, by: null, reason: null });
    const earlyBare = ended({
      kind: "ended_early",
      cause: null,
      by: null,
      reason: null,
      at: "2026-11-14T13:07:00Z",
    });
    if (!timed || !earlyBare) throw new Error("ended");
    expect(endedLine(timed, "Northlight", NOW)).toBe(
      "Canceled at 12:58Z; who and why weren't recorded.",
    );
    expect(endedLine(earlyBare, "Northlight", NOW)).toBe(
      "Ended early at 13:07Z; who and why weren't recorded.",
    );
    expect(endedTag(bare)).toEqual({ state: "off", label: "Canceled" });
    const earlyNoTime = ended({
      kind: "ended_early",
      cause: null,
      by: null,
      at: null,
      reason: null,
    });
    if (!earlyNoTime) throw new Error("ended");
    expect(endedLine(earlyNoTime, "Northlight", NOW)).toBe(
      "Ended early; when, who and why weren't recorded.",
    );
    const rejected = ended({
      ...sys,
      cause: "provider_rejected",
      reason: "delivery_descriptor_conflicts_with_transport",
    });
    const unknownCode = ended({ ...sys, cause: "provider_failed", reason: "station_busy_42" });
    if (!rejected || !unknownCode) throw new Error("ended");
    expect(endedLine(rejected, "Northlight", NOW)).toBe(
      "Canceled by Cadence at 12:58Z: Northlight rejected the booking for this pass (its delivery settings don't match the transport set up in Cadence).",
    );
    expect(endedCode(rejected)).toBe("delivery_descriptor_conflicts_with_transport");
    expect(endedLine(unknownCode, "Northlight", NOW)).toBe(
      "Canceled by Cadence at 12:58Z: Northlight couldn't book this pass.",
    );
    expect(endedCode(failed)).toBeNull();
    const split = ended({
      ...sys,
      cause: "provider_rejected",
      reason: "Antenna 2 is down",
      reason_code: "delivery_descriptor_conflicts_with_transport",
    });
    const textOnly = ended({
      ...sys,
      cause: "provider_failed",
      reason: "no_slot",
      reason_code: null,
    });
    if (!split || !textOnly) throw new Error("ended");
    expect(endedLine(split, "Northlight", NOW)).toBe(
      "Canceled by Cadence at 12:58Z: Northlight rejected the booking for this pass (its delivery settings don't match the transport set up in Cadence: “Antenna 2 is down”).",
    );
    expect(endedCode(split)).toBe("delivery_descriptor_conflicts_with_transport");
    // With reason_code sent, reason is never guessed to be a code.
    expect(endedLine(textOnly, "Northlight", NOW)).toBe(
      "Canceled by Cadence at 12:58Z: Northlight couldn't book this pass (“no_slot”).",
    );
    expect(endedCode(textOnly)).toBeNull();
  });

  it("words each refusal", () => {
    expect(refusalWords(conflict("contact_not_cancelable", { state: "active" }))).toBe(
      "Not canceled: the contact started meanwhile. End it now instead.",
    );
    expect(refusalWords(conflict("contact_not_cancelable", { state: "ended" }))).toBe(
      "Not canceled: the contact has already ended.",
    );
    expect(refusalWords(conflict("contact_not_live", { state: "not_started" }))).toBe(
      "Not ended: the contact hasn't started. Cancel it instead.",
    );
    expect(refusalWords(conflict("contact_not_live", { state: "canceled" }))).toBe(
      "Not ended: the contact was canceled.",
    );
    expect(refusalWords(conflict("contact_not_live", { state: "ended" }))).toBe(
      "Not ended: the contact has already ended.",
    );
    expect(refusalWords({ kind: "not_found", code: "no_scheduled_contact", message: "No." })).toBe(
      "Not canceled: this pass has no contact in Cadence.",
    );
  });
});
