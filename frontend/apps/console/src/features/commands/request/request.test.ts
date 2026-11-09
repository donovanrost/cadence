import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { preflightReader, type Preflight } from "../groups/api.ts";
import { groupOf, showBody } from "../groups/fixtures.ts";
import { eventText } from "../groups/words.ts";
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

describe("approve decision", () => {
  it("offers GO excluding only the flagged targets", () => {
    const flagged = flaggedTargets(review([contactHold]), name);
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
    expect(headline(g)).toBe("2 executed · not verifiable");
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
    expect(headline(g)).toBe("1 of 3 verified · 1 need you");
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
