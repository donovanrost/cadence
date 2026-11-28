import { describe, expect, it } from "vite-plus/test";
import { groupOf } from "./fixtures.ts";
import { expiryCounts, expirySummary, targetExpired } from "./expiry.ts";
import { targetLook } from "./matrix.ts";

const base = groupOf();
const t0 = base.targets[0];
const m0 = t0?.members[0];
if (!t0 || !m0) throw new Error("fixture");
const target = (id: string, stages: (typeof m0.stage)[], expired: boolean) => ({
  ...t0,
  spacecraft_id: id,
  stage: stages.at(-1) ?? t0.stage,
  members: stages.map((stage, i) => ({
    ...m0,
    request_id: `${id}-${i}`,
    position: i,
    stage,
    end_reason: expired && stage === "canceled" ? ("expired" as const) : null,
  })),
});
const group = (targets: ReturnType<typeof target>[]) => ({
  ...base,
  release: { not_before: null, expires_at: "2026-11-16T04:00:00Z", priority: 3 },
  targets,
});

const today = new Date("2026-11-16T05:00:00Z");

describe("an expired request (ux U75, DECISIONS #97)", () => {
  it("counts what went out and what expired, and says so", () => {
    // #795: the counts are the server's (U75), never a tally of the targets on screen.
    const g = {
      ...group([
        target("a", ["verified", "verified", "canceled"], true),
        target("b", ["canceled", "canceled"], true),
      ]),
      expiry: { expires_at: "2026-11-16T04:00:00Z", expired: 3, sent: 2, total: 5 },
    };
    expect(expiryCounts(g)).toEqual({ sent: 2, expired: 3, total: 5 });
    expect(expirySummary(g, today)).toBe(
      "The request expired at 04:00Z after 2 of 5 uplinks went out. The other 3 weren't sent.",
    );
    const none = {
      ...group([target("b", ["canceled"], true)]),
      expiry: { expires_at: "2026-11-16T04:00:00Z", expired: 1, sent: 0, total: 1 },
    };
    expect(expirySummary(none, new Date("2026-11-17T01:00:00Z"))).toBe(
      "The request expired at 11-16 04:00Z before any uplink went out.",
    );
    expect(expirySummary(group([target("c", ["verified"], false)]))).toBeNull();
  });
  it("gives an expired target its own look, not 'canceled'", () => {
    const expired = target("b", ["canceled"], true);
    expect(targetExpired(expired)).toBe(true);
    expect(targetLook(expired)).toBe("expired");
    expect(targetLook(target("c", ["canceled"], false))).toBe("excluded");
  });
});

describe("U75 from api's expiry fields (be3fa592b)", () => {
  it("prefers the server's counts and words the list row", async () => {
    const { expiredRowLabel } = await import("./expiryReader.ts");
    const g = {
      ...group([target("a", ["verified"], false)]),
      expiry: { expires_at: "2026-11-16T04:00:00Z", expired: 3, sent: 2, total: 5 },
    };
    expect(expiryCounts(g)).toEqual({ sent: 2, expired: 3, total: 5 });
    expect(expiredRowLabel({ expires_at: "x", expired: 3, sent: 2, total: 5 })).toBe(
      "Expired · 2 of 5 sent",
    );
    expect(expiredRowLabel({ expires_at: "x", expired: 3, sent: 0, total: 3 })).toBe("Expired");
  });
  it("logs the expiry once: 'Expired at 04:00Z · 2 uplinks sent, 3 not sent'", async () => {
    const { eventText } = await import("./words.ts");
    const at = new Date().toISOString().slice(0, 10) + "T04:00:00Z";
    const e = (payload: { sent: number; not_sent: number }) => {
      const ev = groupOf({
        events: [{ id: "ev", kind: "expired", actor: { actor_kind: "system" }, at, payload }],
      }).events[0];
      if (!ev) throw new Error("fixture");
      return ev;
    };
    const nameOf = () => "Cadence";
    expect(eventText(e({ sent: 2, not_sent: 3 }), nameOf, [], {})).toBe(
      "Expired at 04:00Z · 2 uplinks sent, 3 not sent",
    );
    expect(eventText(e({ sent: 0, not_sent: 3 }), nameOf, [], {})).toBe(
      "Expired at 04:00Z · nothing sent",
    );
  });
});
