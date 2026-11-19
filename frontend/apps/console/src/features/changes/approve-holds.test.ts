import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, outcomeUnknown, type ApiError, type RemoteState } from "@/api";
import type { MissionId } from "@/api/index.ts";
import { previewReader, reviewChangeSet, type Preview } from "./actions.ts";
import { checksRefusal, HOLD_STANDS } from "./checkRefusals.ts";
import ReviewPanel from "./ReviewPanel.vue";
import { changeSet, type ConfigState } from "./shapes.ts";

/** #376 (#262's console half; ux U79 as amended by #374): holds and failed checks at review. */
vi.mock("./actions.ts", async (original) => ({
  ...(await original<typeof import("./actions.ts")>()),
  reviewChangeSet: vi.fn(),
}));
const review = vi.mocked(reviewChangeSet);

const TRY_AGAIN = "Try again; if it keeps happening, tell the team that runs Cadence for you.";
const holdsBlocking: ApiError = {
  kind: "conflict",
  code: "holds_blocking",
  message: "Not approved: a blocking hold stands …",
  details: null,
};
const previewFailed: ApiError = {
  kind: "unavailable",
  status: 503,
  message: "Cadence couldn't run the checks.",
  serverCode: "preview_failed",
};

describe("checksRefusal (#374's words)", () => {
  it("words a failed preview by the act, with the code in Technical details", () => {
    expect(checksRefusal(previewFailed, "approve")).toEqual({
      changed: false,
      sentence: `Not approved: Cadence couldn't run the checks, so nothing was applied and the change set stays in review. Your approval wasn't recorded. ${TRY_AGAIN}`,
      technical: "preview_failed",
    });
    expect(checksRefusal(previewFailed, "apply")?.sentence).toBe(
      `Not applied: Cadence couldn't run the checks, so nothing changed. ${TRY_AGAIN}`,
    );
    expect(checksRefusal(previewFailed, "request_review")?.sentence).toBe(
      `Not sent for review: Cadence couldn't run the checks, so nothing changed. ${TRY_AGAIN}`,
    );
  });

  it("words a blocking hold at approve; apply keeps its own line", () => {
    expect(checksRefusal(holdsBlocking, "approve")).toEqual({
      changed: false,
      sentence:
        "Not approved: a blocking hold stands, so nothing was applied and the change set stays in review. Your approval wasn't recorded. Approve it once the hold clears; the checks show it.",
    });
    expect(checksRefusal(holdsBlocking, "apply")).toBeNull();
  });

  it("leaves every other refusal to the usual words", () => {
    const other: ApiError = {
      kind: "conflict",
      code: "checks_failed",
      message: "x",
      details: null,
    };
    expect(checksRefusal(other, "approve")).toBeNull();
  });

  it("a 503 preview_failed is settled (nothing written), never 'unclear' (#262)", () => {
    expect(outcomeUnknown(previewFailed)).toBe(false);
    expect(outcomeUnknown({ ...previewFailed, serverCode: "something_else" })).toBe(true);
  });
});

const actor = { kind: "user", id: "u1", name: "Mira K." };
function set() {
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
    viewer: { can_review: true, review_blocked_reason: null },
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}
function checks(blocking: boolean, requestedAt = new Date()): RemoteState<Preview> {
  const items = blocking
    ? [{ kind: "spacecraft", reason: "spacecraft_commands_waiting", blocking: true }]
    : [];
  const r = decode(previewReader, {
    verdict: blocking ? "hold" : "go",
    checks: [{ key: "compatibility", verdict: blocking ? "hold" : "go", items }],
    effects: [],
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return { status: "ready", value: r.value, receivedAt: new Date(), requestedAt };
}

describe("#376: Approve and a blocking hold", () => {
  const config = { head: { revision: 5 } } as ConfigState;
  const panel = (preview: RemoteState<Preview>) =>
    mount(ReviewPanel, {
      props: { missionId: "m1" as MissionId, config, changeSet: set(), preview },
    });
  const approve = (w: ReturnType<typeof panel>) => w.findAll("button")[0];
  const sendBack = (w: ReturnType<typeof panel>) => w.findAll("button")[1];
  beforeEach(() => review.mockReset());

  it("disables Approve up front with U79's reason; Send back is unaffected", async () => {
    const w = panel(checks(true));
    await w.find("textarea, input").setValue("Looks right");
    expect(approve(w)?.attributes("aria-disabled")).toBe("true");
    expect(w.get("[data-hold-stands]").text()).toBe(HOLD_STANDS);
    expect(w.findAll(".sr-only").map((s) => s.text())).toContain(HOLD_STANDS);
    expect(sendBack(w)?.attributes("aria-disabled")).toBeUndefined();
  });

  it("after a 409 holds_blocking, Approve waits for a reload that shows the hold cleared", async () => {
    review.mockResolvedValue({ ok: false, error: holdsBlocking });
    const w = panel(checks(false));
    await w.find("textarea, input").setValue("Looks right");
    await approve(w)?.trigger("click");
    await flushPromises();
    expect(w.text()).toContain("Not approved: a blocking hold stands");
    expect(approve(w)?.attributes("aria-disabled")).toBe("true");
    expect(w.get("[data-hold-stands]").text()).toBe(HOLD_STANDS);

    // #395: a read already in flight at the 409 (older answer, no hold) doesn't clear it.
    await w.setProps({ preview: checks(false, new Date(Date.now() - 60_000)) });
    expect(approve(w)?.attributes("aria-disabled")).toBe("true");
    // A reload that still shows the hold keeps it disabled; one without it clears it.
    await w.setProps({ preview: checks(true) });
    expect(approve(w)?.attributes("aria-disabled")).toBe("true");
    await w.setProps({ preview: checks(false) });
    expect(approve(w)?.attributes("aria-disabled")).toBeUndefined();
    expect(w.find("[data-hold-stands]").exists()).toBe(false);
  });

  it("after a 503 preview_failed, Approve stays enabled, and the code is in Technical details", async () => {
    review.mockResolvedValue({ ok: false, error: previewFailed });
    const w = panel(checks(false));
    await w.find("textarea, input").setValue("Looks right");
    await approve(w)?.trigger("click");
    await flushPromises();
    expect(w.text()).toContain("Not approved: Cadence couldn't run the checks");
    expect(w.get("details").text()).toContain("preview_failed");
    expect(approve(w)?.attributes("aria-disabled")).toBeUndefined();
  });
});
