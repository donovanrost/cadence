import { describe, expect, it } from "vite-plus/test";
import { decoders as d } from "@/api";
import { planDetailReader } from "./api.ts";
import { planErrorText } from "./errors.ts";
import {
  expiredLine,
  expiredReader,
  lifecycleRefusal,
  partialApproval,
  supersededByLine,
  supersededByReader,
} from "./lifecycle.ts";

const now = new Date("2026-11-16T12:00:00Z");
const conflict = (code: string, details: unknown) =>
  ({ kind: "conflict", code, message: "x", details }) as const;

describe("U61 superseded_by", () => {
  it("names the replacing revision, its author and the time", () => {
    const s = d.decode(supersededByReader, {
      plan_id: "contact_plan_44",
      revision: 44,
      author: { id: "user_1", name: "Mira K." },
      at: "2026-11-16T10:05:00Z",
    });
    expect(s.ok && s.value && supersededByLine(s.value, now)).toBe(
      "Superseded by R44 (Mira K.) at 10:05Z.",
    );
    const earlier = d.decode(supersededByReader, {
      plan_id: "contact_plan_44",
      revision: 44,
      author: null,
      at: "2026-11-15T10:05:00Z",
    });
    expect(earlier.ok && earlier.value && supersededByLine(earlier.value, now)).toBe(
      "Superseded by R44 at 11-15 10:05Z.",
    );
  });

  it("is read from the plan detail, and null when absent", () => {
    const detail = (superseded_by: unknown) =>
      planDetailReader({
        id: "p",
        version: 1,
        state: "superseded",
        window: { from: null, to: null },
        author: null,
        counts: { passes: 0, minutes: 0, conflicts: 0, unsatisfied: 0 },
        ready_to_approve: false,
        updated_at: "2026-11-10T10:00:00Z",
        passes: [],
        demand: { rule_met: 0, rule_total: 0, spacecraft: [], rules: [] },
        unmet: [],
        conflicts: [],
        ...(superseded_by === undefined ? {} : { superseded_by }),
      });
    expect(detail(undefined).superseded_by).toBeNull();
    expect(detail(null).superseded_by).toBeNull();
    expect(
      detail({ plan_id: "q", revision: 2, author: null, at: "2026-11-10T11:00:00Z" }).superseded_by,
    ).toEqual({ plan_id: "q", revision: 2, author: null, at: "2026-11-10T11:00:00Z" });
  });
});

describe("U61 approval refusals", () => {
  it("words a day another plan covers, with its state word and an Open action", () => {
    const r = lifecycleRefusal(
      conflict("contact_plan_day_already_planned", {
        plan_id: "contact_plan_39",
        revision: 39,
        state: "executing",
        requirements: 212,
        day: "2026-11-16",
      }),
      now,
    );
    expect(r?.text).toBe(
      "Not approved: R39 (booking) already covers 212 of these requirements for 11-16. Open R39, or send this plan back.",
    );
    expect(r?.open).toEqual({ planId: "contact_plan_39", label: "Open R39", day: "2026-11-16" });
  });

  it("words a replaced plan and an all-expired one", () => {
    expect(
      lifecycleRefusal(
        conflict("contact_plan_replaced", {
          plan_id: "contact_plan_44",
          revision: 44,
          at: "2026-11-16T10:05:00Z",
        }),
        now,
      )?.text,
    ).toBe("Not approved: R44 replaced this plan at 10:05Z.");
    const all = lifecycleRefusal(
      conflict("contact_plan_all_opportunities_expired", { expired_count: 36, day: "2026-11-16" }),
      now,
    );
    expect(all?.text).toBe(
      "Not approved: all 36 of its passes have already started, so nothing could be booked.",
    );
    expect(all?.planRestOf).toBe("2026-11-16");
  });

  it("still refuses in words when details are missing, and planErrorText uses them", () => {
    expect(planErrorText(conflict("contact_plan_replaced", null))).toBe(
      "Not approved: a newer plan replaced this one.",
    );
    expect(lifecycleRefusal(conflict("plan_changed", null), now)).toBeNull();
  });
});

describe("U61 partial approval", () => {
  it("says what's booking and what had already started", () => {
    const e = d.decode(expiredReader, {
      count: 36,
      reservable_count: 1476,
      items: [
        {
          spacecraft: { id: "sc_1", name: "EARENDIL-001" },
          station: { ref: "svalbard-1", id: null, code: "SVA", name: null },
          aos: "2026-11-16T00:10:00Z",
        },
      ],
    });
    expect(e.ok && e.value && partialApproval(e.value)).toBe(
      "Approved. Booking 1,476 passes; 36 had already started, so they weren't booked.",
    );
  });
});

describe("an expired pass's line (#190, ux U25)", () => {
  it("names the spacecraft, says Unknown spacecraft without a name, never its id", () => {
    const e = d.decode(expiredReader, {
      count: 2,
      reservable_count: 0,
      items: [
        {
          spacecraft: { id: "sc_1", name: "EARENDIL-001" },
          station: null,
          aos: "2026-11-16T12:10:00Z",
        },
        { spacecraft: { id: "sc_2", name: null }, station: null, aos: "2026-11-16T12:20:00Z" },
      ],
    });
    const items = e.ok && e.value ? e.value.items : [];
    expect(items.map((i) => expiredLine(i, now).split(" · ")[0])).toEqual([
      "EARENDIL-001",
      "Unknown spacecraft",
    ]);
  });
});
