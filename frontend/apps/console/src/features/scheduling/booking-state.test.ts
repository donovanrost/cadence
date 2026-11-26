import { describe, expect, it } from "vite-plus/test";
import type { PlanPass } from "./api.ts";
import { booking, station } from "./fixtures.ts";
import { bookingLook, isBooking, reasonWords, rejectedRows } from "./booking-state.ts";

const pass = (id: string, b: PlanPass["booking"]): PlanPass => ({
  snapshot_id: id,
  spacecraft_id: "sc1",
  station: station({ ref: "svb", id: "gs_svb", code: "SVB-1", name: "Svalbard" }),
  starts_at: "2026-11-13T03:00:00Z",
  ends_at: "2026-11-13T03:08:00Z",
  synthetic: false,
  locked: false,
  expires_at: null,
  booking: b,
  listener_overlap: undefined,
});

describe("K1 per-contact booking (api 8e)", () => {
  it("draws each state with a word, and nothing special before execution or for an unknown state", () => {
    expect(bookingLook(booking("confirmed", null))).toEqual({
      kind: "own",
      word: "Confirmed",
    });
    expect(bookingLook(booking("rejected", "no_capacity"))?.kind).toBe("clash");
    expect(bookingLook(booking("uncertain", null))?.kind).toBe("unconfirmed");
    expect(bookingLook(booking("never_sent", "sending"))?.word).toBe("Requested · sending");
    expect(bookingLook(null)).toBeNull();
    expect(bookingLook(booking({ unrecognized: "teleported" }, null))).toBeNull();
  });

  it("turns rejected and failed bookings into Demand rows, with the server's reason when it has one", () => {
    const rows = rejectedRows([
      pass("a", booking("confirmed", null)),
      pass("b", booking("rejected", "antenna_fault")),
      pass("c", booking("failed", null)),
      pass("d", null),
    ]);
    expect(rows.map((r) => r.sentence)).toEqual([
      "Rejected · SVB-1 03:00Z: antenna fault.",
      "Failed · SVB-1 03:00Z: the provider didn't say why.",
    ]);
  });

  it("uses ux's reason words and next steps, Lost and Not sent included", () => {
    const rows = rejectedRows([
      pass("a", booking("rejected", "no_capacity")),
      pass("b", booking("failed", "booking_lost")),
      pass("c", booking("never_sent", "mission_provider_not_found")),
      pass("d", booking("never_sent", "sending")),
      pass("e", booking("failed", "invalid_contact_interval")),
    ]);
    expect(rows.map((r) => [r.sentence, r.next])).toEqual([
      ["Rejected · SVB-1 03:00Z: the station has no capacity then.", "replan"],
      ["Lost · SVB-1 03:00Z: the provider dropped a confirmed booking.", "replan"],
      ["Not sent · SVB-1 03:00Z: this mission has no provider set up for that station.", "setup"],
      [
        "Failed · SVB-1 03:00Z: Cadence couldn't build the booking request. This needs a Cadence fix.",
        null,
      ],
    ]);
    expect(rows[3]?.code).toBe("invalid_contact_interval");
  });

  it("adds the provider's text, retry words and the resolving operator when the read has them", () => {
    const [row] = rejectedRows([
      pass("a", {
        state: "rejected",
        reason: "no_capacity",
        at: "2026-11-13T03:00:00Z",
        detail: "Station full",
        retryable: null,
        retry_after_seconds: null,
        resolved: null,
      }),
    ]);
    expect(row?.sentence).toBe(
      'Rejected · SVB-1 03:00Z: the station has no capacity then ("Station full").',
    );
    const [retry] = rejectedRows([
      pass("b", {
        state: "failed",
        reason: "provider_unavailable",
        at: "2026-11-13T03:00:00Z",
        detail: null,
        retryable: true,
        retry_after_seconds: 720,
        resolved: null,
      }),
    ]);
    expect(retry?.sentence).toBe(
      "Failed · SVB-1 03:00Z: the provider couldn't be reached. Cadence retries at 03:12Z.",
    );
    expect(
      reasonWords("operator_not_booked", {
        state: "failed",
        reason: "operator_not_booked",
        at: null,
        detail: null,
        retryable: null,
        retry_after_seconds: null,
        resolved: { by: { kind: "user", id: "u1", name: "Mira K." }, at: "2026-11-13T10:52:00Z" },
      }).text,
    ).toBe("marked not booked by Mira K. at 10:52Z");
    expect(reasonWords("provider_declined").text).toBe('the provider answered "declined"');
  });

  it("treats a plan that has gone out for booking as booking, not a draft (qa #52)", () => {
    expect(isBooking("reserved")).toBe(true);
    expect(isBooking("partially_reserved")).toBe(true);
    expect(isBooking("executing")).toBe(true);
    expect(isBooking("draft")).toBe(false);
    expect(isBooking("pending_approval")).toBe(false);
    expect(isBooking("unrecognized")).toBe(false);
  });
});
