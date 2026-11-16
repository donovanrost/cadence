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
    const g = group([
      target("a", ["verified", "verified", "canceled"], true),
      target("b", ["canceled", "canceled"], true),
    ]);
    expect(expiryCounts(g)).toEqual({ sent: 2, expired: 3, total: 5 });
    expect(expirySummary(g, today)).toBe(
      "The request expired at 04:00Z after 2 of 5 uplinks went out. The other 3 weren't sent.",
    );
    expect(
      expirySummary(group([target("b", ["canceled"], true)]), new Date("2026-11-17T01:00:00Z")),
    ).toBe("The request expired at 11-16 04:00Z before any uplink went out.");
    expect(expirySummary(group([target("c", ["verified"], false)]))).toBeNull();
  });
  it("gives an expired target its own look, not 'canceled'", () => {
    const expired = target("b", ["canceled"], true);
    expect(targetExpired(expired)).toBe(true);
    expect(targetLook(expired)).toBe("expired");
    expect(targetLook(target("c", ["canceled"], false))).toBe("excluded");
  });
});
