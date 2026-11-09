import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { preflightReader, type Preflight } from "../groups/api.ts";
import { groupOf, showBody } from "../groups/fixtures.ts";
import { eventText, memberStageWord, statusTag } from "../groups/words.ts";
import { inTab } from "../list/list.ts";
import type { GroupRow } from "../groups/api.ts";
import { cannotDecide, decisionOptions, flaggedTargets, noGoAfter } from "./decision.ts";
import { abortable, headline, pipeline } from "./uplink.ts";

const target = (id: string, stage: string) => ({
  ...showBody.targets[0],
  spacecraft_id: id,
  name: id.toUpperCase(),
  stage,
  members: (showBody.targets[0]?.members ?? []).map((m) => ({ ...m, stage })),
});
const two = groupOf({
  target_count: 2,
  targets: [target("sc-1", "awaiting_go"), target("sc-2", "awaiting_go")],
});

function review(checks: unknown[]): Preflight {
  const r = decode(preflightReader, {
    valid: true,
    digest: "d",
    members: 2,
    second_go_required: true,
    targets: [],
    checks,
  });
  if (!r.ok) throw r.error;
  return r.value;
}
const contactHold = {
  key: "contact",
  result: "hold",
  per_target: [
    { spacecraft_id: "sc-1", result: "go", next_contact: null },
    { spacecraft_id: "sc-2", result: "hold", next_contact: null },
  ],
  evidence: {},
};
const name = (id: string) => id.toUpperCase();
const actorDoc = { actor_kind: "user", user_id: "user-2" };

describe("approve decision", () => {
  it("offers GO excluding only the flagged targets", () => {
    const identity = {
      key: "identity",
      result: "no_go",
      per_target: [{ spacecraft_id: "sc-2", result: "no_go", reason: "no_uplink_route" }],
      evidence: {},
    };
    const flagged = flaggedTargets(review([contactHold, identity]), name);
    expect(flagged).toEqual([{ spacecraftId: "sc-2", name: "SC-2" }]);
    const opts = decisionOptions(two, flagged);
    expect(opts.map((o) => [o.value, o.commitLabel])).toEqual([
      ["go", "Sign GO · 2 targets"],
      ["go_excluding", "Sign GO · 1 target"],
      ["send_back", "Send back"],
      ["no_go", "Sign NO-GO"],
    ]);
    expect(decisionOptions(two, []).map((o) => o.value)).toEqual(["go", "send_back", "no_go"]);
  });

  it("blocks GO on a NO-GO unless excluding clears every failing target", () => {
    const catalog = {
      key: "catalog",
      result: "no_go",
      per_target: [{ spacecraft_id: "sc-2", result: "no_go", reason: [] }],
      evidence: {},
    };
    const r = review([catalog]);
    expect(noGoAfter(r, new Set())).toBe("The catalog re-check is NO-GO.");
    expect(noGoAfter(r, new Set(["sc-2"]))).toBeNull();
    expect(noGoAfter(review([{ ...catalog, per_target: [] }]), new Set(["sc-2"]))).not.toBeNull();
  });

  it("explains who may decide; never your own request", () => {
    const people = (id: string | null) => (id === "user-2" ? "Ana" : "Someone");
    expect(cannotDecide(two, "user-1", true, people)).toMatch(/can't approve your own request/);
    expect(cannotDecide(two, "user-9", false, people)).toMatch(/needs command approval/);
    expect(cannotDecide(two, "user-9", true, people)).toBeNull();
    const named = groupOf({ awaiting_me: false, requested_approver_user_id: "user-2" });
    expect(cannotDecide(named, "user-9", true, people)).toBe("Ana was asked for this GO.");
  });
});

describe("uplink", () => {
  it("never reads green without a verifier", () => {
    const g = groupOf({
      state: "queued",
      target_count: 2,
      progress: { no_verifier: 2 },
      targets: [target("sc-1", "no_verifier"), target("sc-2", "no_verifier")],
    });
    expect(headline(g, () => "Ana")).toBe("2 executed · not verifiable");
    expect(pipeline(g).find((t) => t.key === "verified")?.value).toBe(0);
    expect(abortable(g)).toBe(false);
  });

  it("counts verified and needs-you, and offers abort while uplinks wait", () => {
    const g = groupOf({
      state: "queued",
      target_count: 3,
      progress: { verified: 1, verify_failed: 1, queued_for_contact: 1 },
      targets: [
        target("sc-1", "verified"),
        target("sc-2", "verify_failed"),
        target("sc-3", "queued_for_contact"),
      ],
    });
    expect(headline(g, () => "Ana")).toBe("1 of 3 verified · 1 need you");
    expect(abortable(g)).toBe(true);
  });

  it("writes request-log lines with names and notes", () => {
    const g = groupOf({
      events: [
        {
          id: "e",
          kind: "sent_back",
          actor: { actor_kind: "user", user_id: "user-2" },
          at: "2026-11-08T02:05:00Z",
          payload: { note: "Wrong plane", excluded: [], approved: 0 },
        },
      ],
    });
    const [e] = g.events;
    expect(e && eventText(e, () => "Ana")).toBe("Ana sent it back: “Wrong plane”");
  });
});

describe("abort event (live shape)", () => {
  it("reads canceled as a count and already_started as ids", () => {
    const g = groupOf({
      state: "aborted",
      events: [
        {
          id: "e1",
          kind: "submitted",
          actor: { actor_kind: "user", user_id: "user-1" },
          at: "2026-11-09T11:06:57Z",
          payload: { members: 1, second_go_required: false },
        },
        {
          id: "e2",
          kind: "aborted",
          actor: { actor_kind: "user", user_id: "user-1" },
          at: "2026-11-09T11:07:02Z",
          payload: { already_started: [], canceled: 1, reason: "e2e" },
        },
      ],
    });
    const [submitted, aborted] = g.events;
    expect(submitted && eventText(submitted, () => "You")).toBe("You submitted 1 uplink");
    expect(aborted && eventText(aborted, () => "You")).toBe(
      "You aborted: “e2e” · 1 canceled, 0 already started",
    );
  });
});

describe("closed requests and exclusions (qa matrix nits)", () => {
  const people = () => "Ana";
  it("says how a closed request closed", () => {
    expect(headline(groupOf({ state: "rejected", decided_by: actorDoc }), people)).toBe(
      "Rejected by Ana · nothing radiated",
    );
    expect(headline(groupOf({ state: "sent_back", decided_by: actorDoc }), people)).toBe(
      "Sent back by Ana · edit and resend",
    );
    expect(headline(groupOf({ state: "aborted", progress: { canceled: 2 } }), people)).toBe(
      "Aborted · nothing radiated",
    );
    expect(memberStageWord("rejected", "sent_back")).toBe("Sent back");
    expect(memberStageWord("rejected", "rejected")).toBe("NO-GO");
  });

  it("doesn't offer exclusions for targets that only wait for a pass", () => {
    expect(flaggedTargets(review([contactHold]), name)).toEqual([]);
    const conflict = {
      key: "identity",
      result: "no_go",
      per_target: [{ spacecraft_id: "sc-2", result: "no_go", reason: "no_uplink_route" }],
      evidence: {},
    };
    expect(flaggedTargets(review([contactHold, conflict]), name)).toEqual([
      { spacecraftId: "sc-2", name: "SC-2" },
    ]);
  });
});

describe("delivered requests stay 'queued' (approval-only state, qa #28)", () => {
  it("tags a released request by its delivery, never just queued", () => {
    expect(statusTag("queued", { queued_for_contact: 2 }, 2).label).toBe(
      "GO given · released to the queue",
    );
    expect(statusTag("queued", { no_verifier: 1 }, 1)).toEqual({
      label: "1/1 delivered",
      state: "stale",
    });
    expect(statusTag("queued", { verified: 2 }, 2).state).toBe("nominal");
    expect(statusTag("queued", { radiating: 1, queued_for_contact: 1 }, 2)).toEqual({
      label: "0/2 delivered",
      state: "live",
    });
    expect(statusTag("queued", { verified: 1, verify_failed: 1 }, 2)).toEqual({
      label: "2/2 delivered · 1 need you",
      state: "crit",
    });
    expect(statusTag("queued", undefined, 1).label).toBe("GO given");
    expect(statusTag("rejected", { rejected: 1 }, 1).label).toBe("NO-GO");
  });

  it("moves a finished run from Released to Closed", () => {
    const row = (progress: GroupRow["progress"]): GroupRow => ({
      id: "g",
      state: "queued",
      title: "t",
      requested_by: { actor_kind: "user", user_id: "u" },
      requested_at: "2026-11-09T15:26:26Z",
      requested_approver_user_id: null,
      member_count: 1,
      target_count: 1,
      command_count: 1,
      second_go_required: false,
      awaiting_me: false,
      operation_id: null,
      progress,
    });
    expect(inTab(row({ no_verifier: 1 }), "closed")).toBe(true);
    expect(inTab(row({ no_verifier: 1 }), "queued")).toBe(false);
    expect(inTab(row({ queued_for_contact: 1 }), "queued")).toBe(true);
    expect(inTab(row(undefined), "queued")).toBe(true);
  });
});
