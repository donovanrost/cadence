import { missionId as missionIdOf } from "@/api/index.ts";
import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { reviewBlocked } from "./review-block.ts";
import ReviewPanel from "./ReviewPanel.vue";
import { changeSet, type ConfigState } from "./shapes.ts";

const actor = { kind: "user", id: "u1", name: "Mira K." };
function set(extra: Record<string, unknown> = {}) {
  const r = decode(changeSet, {
    id: "cs9",
    version: 1,
    state: "in_review",
    base_revision: 5,
    opened_at: "2026-11-16T19:00:00Z",
    opened_by: actor,
    staged_count: 0,
    changes: [],
    withdrawn: [],
    authors: [actor],
    submitted_by: actor,
    submitted_at: "2026-11-16T19:05:00Z",
    reason: "Batch 2",
    approval_required: true,
    reviews: [],
    failure: null,
    applied_revision: null,
    ...extra,
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}
const blockedAs = (reason: unknown) => ({
  viewer: { can_review: false, review_blocked_reason: reason },
});
const AUTHOR =
  "You staged part of this change set or sent it for review, so another person reviews it.";
const UNKNOWN = "You can't review this change set, so another person reviews it.";

describe("#320: review blocked before the click, from the server's viewer (U97)", () => {
  it("blocks an author or submitter with ux's line", () => {
    expect(reviewBlocked(set(blockedAs("reviewer_is_author")))).toEqual({
      line: AUTHOR,
      code: null,
    });
  });

  it("blocks with the unknown-reason line, never the author's, for a reason it doesn't know (U20)", () => {
    expect(reviewBlocked(set(blockedAs("quorum_reached")))).toEqual({
      line: UNKNOWN,
      code: "quorum_reached",
    });
    expect(reviewBlocked(set(blockedAs(null)))).toEqual({ line: UNKNOWN, code: null });
  });

  it("doesn't block when the viewer may review or the server doesn't say", () => {
    const can = { viewer: { can_review: true, review_blocked_reason: null } };
    expect(reviewBlocked(set(can))).toBeNull();
    expect(reviewBlocked(set())).toBeNull();
    expect(reviewBlocked(set({ viewer: null }))).toBeNull();
  });
});

describe("#320: the review panel", () => {
  const config = { head: { revision: 5 } } as ConfigState;
  const panel = (extra: Record<string, unknown>) =>
    mount(ReviewPanel, {
      props: {
        missionId: missionIdOf("m1"),
        config,
        changeSet: set(extra),
        preview: { status: "loading" } as const,
      },
    });
  const buttons = (w: ReturnType<typeof panel>) => w.findAll("button");

  it("disables Approve and Send back for an author, with the line, even with a comment", async () => {
    const w = panel(blockedAs("reviewer_is_author"));
    await w.find("textarea, input").setValue("Looks right");
    expect(w.get("[data-review-blocked]").text()).toBe(AUTHOR);
    for (const b of buttons(w)) expect(b.attributes("aria-disabled")).toBe("true");
    // #313 (A6): the reason is said once; the field and both buttons point at that one line.
    const lineId = w.get("[data-review-blocked]").attributes("id");
    expect(lineId).toBeTruthy();
    for (const b of buttons(w)) expect(b.attributes("aria-describedby")).toBe(lineId);
    const field = w.get("input");
    expect(field.attributes("aria-describedby")?.split(" ")).toContain(lineId);
    expect(w.findAll(".sr-only").map((s) => s.text())).not.toContain(AUTHOR);
    // The Comment typed so far is kept, read-only (never disabled).
    const input = field.element;
    if (!(input instanceof HTMLInputElement)) throw new Error("not an input");
    expect(input.readOnly).toBe(true);
    expect(input.disabled).toBe(false);
    expect(input.value).toBe("Looks right");
    expect(w.text()).not.toContain("Technical details");
  });

  it("puts an unknown reason's code in Technical details", () => {
    const w = panel(blockedAs("quorum_reached"));
    expect(w.get("[data-review-blocked]").text()).toBe(UNKNOWN);
    expect(w.get("details").text()).toContain("review_blocked_reason: quorum_reached");
  });

  it("leaves a reviewer's decisions to the comment rule", async () => {
    const w = panel({ viewer: { can_review: true, review_blocked_reason: null } });
    expect(w.find("[data-review-blocked]").exists()).toBe(false);
    await w.find("textarea, input").setValue("Looks right");
    for (const b of buttons(w)) expect(b.attributes("aria-disabled")).toBeUndefined();
  });
});
