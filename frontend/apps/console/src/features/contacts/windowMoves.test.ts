import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { passReader } from "./api.ts";
import { listensUntil, moveDuration, windowMoveLine, windowMoves } from "./windowMoves.ts";

/** A move as GET /passes/:id carries it (decoded through the pass reader). */
const passWithMoves = (moves: unknown[], after: [string, string]) =>
  decode(passReader, {
    id: "pass-3",
    kind: "contact",
    state: "confirmed",
    pass_phase: "scheduled",
    delivery_state: "pending",
    spacecraft_id: "spacecraft-earendil-003",
    spacecraft: { id: "spacecraft-earendil-003", name: "EARENDIL-003", scid: 3 },
    station: { ref: "brs", id: null, code: "BRS", name: "Brisbane" },
    antenna: null,
    starts_at: after[0],
    ends_at: after[1],
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
    window_moves: moves,
  });
const moveOf = (before: [string, string], after: [string, string], at = "2026-11-14T12:05:00Z") => {
  const r = passWithMoves(
    [
      {
        at,
        before: { starts_at: before[0], ends_at: before[1] },
        after: { starts_at: after[0], ends_at: after[1] },
        classification: "observed",
        provider_change_id: "chg-1",
      },
    ],
    after,
  );
  if (!r.ok) throw new Error(r.error.message);
  const m = windowMoves(r.value.window_moves)[0];
  if (!m) throw new Error("no move");
  return m;
};
const T = (hms: string) => `2026-11-14T${hms}Z`;

describe("U56 window moves in the pass history", () => {
  it("reads a revision with no window (qa 11-16, approval_required) and leaves it out", () => {
    const r = passWithMoves(
      [
        {
          at: "2026-11-13T14:30:42.059536Z",
          before: null,
          after: null,
          classification: "approval_required",
          provider_change_id: "provider_change_5lec73hfga_L1LE",
        },
      ],
      [T("12:11:27"), T("12:19:27")],
    );
    if (!r.ok) throw new Error(r.error.message);
    expect(r.value.window_moves).toHaveLength(1);
    expect(windowMoves(r.value.window_moves)).toEqual([]);
  });

  it("words each case to the second, later or earlier", () => {
    expect(
      windowMoveLine(
        moveOf([T("12:10:57"), T("12:18:57")], [T("12:11:27"), T("12:19:27")]),
        "Northlight",
      ),
    ).toBe(
      "Northlight moved this pass 30 s later: now 12:11:27–12:19:27Z (was 12:10:57–12:18:57Z).",
    );
    expect(
      windowMoveLine(
        moveOf([T("13:04:30"), T("13:12:30")], [T("13:04:30"), T("13:13:30")]),
        "Northlight",
      ),
    ).toBe(
      "Northlight moved this pass's LOS 1 min later: now 13:04:30–13:13:30Z (was 13:04:30–13:12:30Z).",
    );
    expect(
      windowMoveLine(moveOf([T("13:05:00"), T("13:12:30")], [T("13:04:30"), T("13:12:30")]), null),
    ).toBe(
      "The provider moved this pass's AOS 30 s earlier: now 13:04:30–13:12:30Z (was 13:05:00–13:12:30Z).",
    );
    expect(
      windowMoveLine(
        moveOf([T("13:04:00"), T("13:12:00")], [T("13:04:30"), T("13:13:30")]),
        "Northlight",
      ),
    ).toBe(
      "Northlight changed this pass's window: now 13:04:30–13:13:30Z (was 13:04:00–13:12:00Z).",
    );
  });

  it("durations and the live listening line", () => {
    expect(moveDuration(30_000)).toBe("30 s");
    expect(moveDuration(120_000)).toBe("2 min");
    expect(moveDuration(-90_000)).toBe("1 min 30 s");
    const m = moveOf([T("12:10:57"), T("12:18:57")], [T("12:11:27"), T("12:19:27")]);
    expect(listensUntil(m, true)).toBe("Cadence now listens until 12:19:27Z.");
    expect(listensUntil(m, false)).toBeNull();
  });

  it("dates a window once on another day, on both ends across midnight", () => {
    const m = moveOf(
      ["2026-11-14T23:59:30Z", "2026-11-15T00:07:30Z"],
      ["2026-11-15T00:00:00Z", "2026-11-15T00:08:00Z"],
      "2026-11-14T23:50:00Z",
    );
    expect(windowMoveLine(m, "Northlight")).toBe(
      "Northlight moved this pass 30 s later: now 11-15 00:00:00–00:08:00Z (was 11-14 23:59:30–11-15 00:07:30Z).",
    );
  });
});
