import { describe, expect, it } from "vite-plus/test";
import type { ResolutionAction } from "./attention.ts";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { resolvedReader, resolvedWords } from "./attention.ts";

const NOW = new Date("2026-11-15T18:28:00Z");

/** The queue item as api serves it (domain + api shape 11-14). */
const item = (o: Record<string, unknown> = {}, priority = 2) => ({
  id: "attention:plan_coverage:2026-11-16",
  priority,
  kind: "attention",
  state: "caution",
  source: "plan_coverage",
  acknowledged: null,
  since: "2026-11-14T03:10:00Z",
  due_at: "2026-11-16T00:28:00Z",
  count: 1,
  spacecraft: [
    {
      id: "spacecraft-earendil-008",
      name: "EARENDIL-008",
      scid: 8,
      plane: 3,
      stale: false,
      last_received_at: null,
      violating_points: null,
      value: null,
      first_crossed_at: null,
      episode_id: null,
      status: null,
      assignee: null,
      acknowledged_by: null,
    },
  ],
  point: null,
  condition: null,
  plane: null,
  command: null,
  outcome: null,
  command_requests: [],
  finding: null,
  attention: {
    id: "2026-11-16",
    source: "plan_coverage",
    conflict: null,
    state: "open",
    acknowledged_by: null,
    contact_id: null,
    station: null,
    provider: null,
    starts_at: null,
    raised_at: "2026-11-15T00:28:00Z",
    provider_message: null,
    day: "2026-11-16",
    first_window_at: "2026-11-16T00:28:00Z",
    due_at: "2026-11-16T00:28:00Z",
    severity: "caution",
    requirements_count: 1512,
    open_requirements_count: 1104,
    plan: {
      id: "plan-41",
      revision: 41,
      state: "pending_approval",
      author: { id: "u-mira", name: "Mira K." },
      submitted_at: "2026-11-11T22:10:00Z",
      sent_back: null,
    },
    approvers: [
      { id: "u-ana", name: "Ana R." },
      { id: "u-owen", name: "Owen P." },
    ],
    viewer_can_approve: false,
    resolution: null,
    ...o,
  },
});

const rowOf = (o: Record<string, unknown> = {}, priority = 2, viewer: string | null = null) => {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
    items: [item(o, priority)],
  });
  if (!r.ok) throw new Error(r.error.message);
  return presentQueue(r.value, NOW, "EARENDIL", viewer)[0];
};

describe("plan_coverage on Now (ux U61)", () => {
  it("pending: names the plan, says nothing is booked, and who it waits on", () => {
    const row = rowOf();
    expect(row?.title).toBe("Plan for 11-16 is awaiting approval");
    expect(row?.sentence).toBe(
      "R41 has waited for approval since 11-11 22:10Z. Nothing is booked for 11-16's 1,512 requirements until it's approved. Waiting on an org admin: Ana R. or Owen P.",
    );
    expect(row?.meta).toBe("FIRST WINDOW 11-16 00:28Z · 1,512 REQUIREMENTS");
    expect(row?.due).toEqual({ label: "", at: "2026-11-16T00:28:00Z" });
    expect(row?.action).toEqual({
      label: "Open plan",
      to: { name: "ops.contacts.plan", query: { day: "2026-11-16", plan: "plan-41" } },
    });
  });

  it("keeps who it waits on even without approver names", () => {
    expect(rowOf({ approvers: [] })?.sentence).toMatch(/Waiting on an org admin\.$/);
  });

  it("an approver who isn't the author gets Review; the author gets the self-approval line", () => {
    const review = rowOf({ viewer_can_approve: true }, 2, "u-ana");
    expect(review?.action.label).toBe("Review");
    expect(review?.primary).toBe(true);
    expect(rowOf({}, 2, "u-mira")?.sentence).toMatch(/You can't approve your own plan\.$/);
  });

  it("sent back, draft, and no plan", () => {
    const back = rowOf({
      plan: {
        id: "plan-41",
        revision: 41,
        state: "draft",
        author: { id: "u-mira", name: "Mira K." },
        submitted_at: "2026-11-11T22:10:00Z",
        sent_back: {
          by: { id: "u-ana", name: "Ana R." },
          at: "2026-11-12T09:40:00Z",
          comment: "Too many KSAT passes.",
        },
      },
    });
    expect(back?.title).toBe("Plan for 11-16 was sent back");
    expect(back?.sentence).toBe(
      "Ana R. sent R41 back at 11-12 09:40Z: “Too many KSAT passes.” Nothing is booked for 11-16's 1,512 requirements until a new plan is approved.",
    );
    const draft = rowOf({
      plan: {
        id: "plan-43",
        revision: 43,
        state: "draft",
        author: { id: "u-mira", name: "Mira K." },
        submitted_at: null,
        sent_back: null,
      },
    });
    expect(draft?.title).toBe("Plan for 11-16 is still a draft");
    expect(draft?.sentence).toBe(
      "R43 (Mira K.) hasn't been submitted. Nothing is booked for 11-16's 1,512 requirements until a plan is approved.",
    );
    const none = rowOf({ plan: null });
    expect(none?.title).toBe("11-16 has no plan yet");
    expect(none?.sentence).toBe("Nothing is planned or booked for 11-16's 1,512 requirements.");
    expect(none?.action).toEqual({
      label: "Plan 11-16",
      to: { name: "ops.contacts.plan", query: { day: "2026-11-16" } },
    });
  });

  it("crit once the first window opened: Plan the rest, never Review, no countdown", () => {
    const row = rowOf({ severity: "crit", viewer_can_approve: true }, 1, "u-ana");
    expect(row?.title).toBe("11-16 started with no approved plan");
    expect(row?.state).toBe("crit");
    expect(row?.sentence).toBe(
      "11-16's first window opened at 11-16 00:28Z and nothing is booked. R41 can't be approved now; a new plan for the rest of the day can still book its 1,104 open requirements.",
    );
    expect(row?.action).toEqual({
      label: "Plan the rest of 11-16",
      to: { name: "ops.contacts.plan", query: { day: "2026-11-16" } },
    });
    expect(row?.due).toBeUndefined();
  });

  it("says how it closed", () => {
    const closed = (action: ResolutionAction, kind: "user" | "system", name: string | null) =>
      resolvedWords(
        {
          id: "attention:plan_coverage:2026-11-16",
          resolved_by: { kind, id: null, name },
          action,
          resolved_at: "2026-11-15T18:02:00Z",
          note: null,
        },
        NOW,
      );
    expect(closed("approved", "user", "Ana R.")).toBe("Approved by Ana R. at 18:02Z.");
    expect(closed("nothing_left", "system", null)).toBe("Nothing is left to plan for 11-16.");
    expect(closed("day_ended", "system", null)).toBe("11-16 ended with no approved plan.");
  });
});

describe("plan_coverage: an approved plan that isn't booking (ux 366240d64, 11fe550bf)", () => {
  const approved = {
    id: "plan-41",
    revision: 41,
    state: "approved",
    author: { id: "u-mira", name: "Mira K." },
    submitted_at: null,
    sent_back: null,
    approved_at: "2026-11-15T22:10:00Z",
    booking: null,
  };
  it("approved, not started: says so and offers Start booking to whoever may book", () => {
    const row = rowOf({ plan: approved, viewer_can_book: true });
    expect(row?.title).toBe("Plan for 11-16 is approved but booking hasn't started");
    expect(row?.sentence).toBe(
      "R41 was approved at 22:10Z, but booking hasn't started. Nothing is booked for 11-16's 1,512 requirements until it does.",
    );
    expect(row?.command?.label).toBe("Start booking");
    expect(row?.command?.kind).toBe("book");
    expect(row?.action.label).toBe("Open plan");
    expect(rowOf({ plan: approved, viewer_can_book: false })?.command).toBeUndefined();
  });
  it("interrupted: how far it got and its last progress, with Continue booking", () => {
    const stopped = {
      ...approved,
      state: "interrupted",
      booking: { reserved: 12, total: 41, last_progress_at: "2026-11-15T22:14:00Z" },
    };
    const row = rowOf({ plan: stopped, viewer_can_book: true });
    expect(row?.title).toBe("Booking for 11-16 stopped");
    expect(row?.sentence).toBe(
      "Booking for R41 stopped with 12 of 41 passes booked; its last progress was at 22:14Z. The other 29 aren't booked until it continues.",
    );
    expect(row?.command?.label).toBe("Continue booking");
    const none = rowOf({
      plan: {
        ...stopped,
        booking: { reserved: 0, total: 41, last_progress_at: "2026-11-15T22:14:00Z" },
      },
    });
    expect(none?.sentence).toBe(
      "Booking for R41 stopped before any pass was booked; its last progress was at 22:14Z.",
    );
  });
  it("words booking_started and a stalled day's end", () => {
    const r = (o: Record<string, unknown>) => {
      const entry = decode(resolvedReader, {
        id: "attention:plan_coverage:2026-11-16",
        resolved_by: { kind: "system", id: null, name: null },
        resolved_at: "2026-11-15T22:11:00Z",
        note: null,
        ...o,
      });
      if (!entry.ok) throw new Error(entry.error.message);
      return resolvedWords(entry.value, NOW);
    };
    expect(r({ action: "booking_started", from_state: "approved" })).toBe(
      "Booking started at 22:11Z.",
    );
    expect(r({ action: "booking_started", from_state: "interrupted" })).toBe(
      "Booking continued at 22:11Z.",
    );
    expect(
      r({ action: "day_ended", from_state: "approved", plan_revision: 41, booking: null }),
    ).toBe("11-16 ended with R41 approved but not booked.");
    expect(
      r({ action: "day_ended", from_state: "interrupted", booking: { reserved: 12, total: 41 } }),
    ).toBe("11-16 ended with 12 of 41 passes booked.");
  });
});
