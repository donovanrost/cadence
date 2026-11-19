import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId, type ApiError } from "@/api/index.ts";
import { approvePlan, submitPlan } from "./plan-actions-api.ts";
import { reviewOps, runReview } from "./review-run.ts";
import { approveRefusal, submitRefusalText } from "./review-words.ts";

vi.mock("./plan-actions-api.ts", () => ({ approvePlan: vi.fn(), submitPlan: vi.fn() }));
const submit = vi.mocked(submitPlan);
const approve = vi.mocked(approvePlan);
afterEach(() => vi.resetAllMocks());

const who = { version: 41, userId: "u-me", day: "2026-11-16" };
const conflict = (code: string, details?: unknown): ApiError => ({
  kind: "conflict",
  code,
  message: code,
  details,
});
const forbidden = (code: string, details?: unknown): ApiError => ({
  kind: "forbidden",
  code,
  message: code,
  details,
});
const self = (because: string) => forbidden("contact_plan_self_approval_forbidden", { because });

/** #257 / U97: each approve refusal says why and that the approval wasn't recorded. */
describe("approve refusals (U97)", () => {
  it("names a self-approval by what the approver did, and offers the A6 reason", () => {
    expect(approveRefusal(self("submitted"), who)).toMatchObject({
      text: "Not approved: you submitted this plan, so another org admin approves it. Your approval wasn't recorded and nothing was booked.",
      because: "submitted",
      code: null,
    });
    expect(approveRefusal(self("edited"), who)).toMatchObject({
      text: "Not approved: you drafted this version of the plan, so another org admin approves it. Your approval wasn't recorded and nothing was booked.",
      because: "edited",
    });
    // A because this console doesn't know: the plain refusal with the code, never a guess.
    expect(approveRefusal(self("delegated"), who)).toMatchObject({
      text: "Not approved: Cadence refused this approval. Your approval wasn't recorded.",
      code: "contact_plan_self_approval_forbidden",
      because: null,
    });
  });

  it("says who decided and when, both or neither, and never an id (U25, U29)", () => {
    const decided = (state: string, by: unknown, at: string | null) =>
      approveRefusal(conflict("plan_not_pending", { state, decided_by: by, decided_at: at }), who);
    const at = "2026-11-19T03:46:00Z";
    expect(decided("executing", { id: "u-ana", name: "Ana R." }, at).text).toMatch(
      /^R41 was already approved by Ana R\. at (11-19 )?03:46Z, so your approval wasn't recorded\. Reload to see it\.$/,
    );
    expect(decided("draft", { id: "u-ana", name: "Ana R." }, at).text).toMatch(
      /already sent back by Ana R\./,
    );
    expect(decided("reserved", { id: "u-me", name: "Me" }, at).text).toMatch(
      /^You already approved R41 at (11-19 )?03:46Z\. Reload to see it\.$/,
    );
    expect(decided("draft", { id: "u-me", name: "Me" }, at).text).toMatch(
      /^You already sent back R41/,
    );
    const none =
      "Not approved: R41 isn't waiting for approval any more, so your approval wasn't recorded. Reload to see it.";
    expect(decided("executing", { id: "u-ana", name: null }, at).text).toBe(none);
    expect(decided("executing", { id: "u-ana", name: "Ana R." }, null).text).toBe(none);
    expect(approveRefusal(conflict("plan_not_pending"), who).text).toBe(none);
  });

  it("words a changed, missing, foreign or unknown refusal", () => {
    expect(approveRefusal(conflict("plan_changed"), who).text).toBe(
      "Not approved: R41 changed after you opened it, so it isn't what you reviewed. Your approval wasn't recorded. Reload to review it again.",
    );
    expect(
      approveRefusal({ kind: "not_found", code: "plan_not_found", message: "" }, who).text,
    ).toBe("Not approved: Cadence can't find this plan any more. Reload to see 11-16's plans.");
    expect(approveRefusal(forbidden("forbidden"), who).text).toBe(
      "Not approved: only an org admin approves contact plans. Your approval wasn't recorded.",
    );
    expect(approveRefusal(conflict("plan_superseded"), who).text).toMatch(
      /^Not approved: contact rules changed/,
    );
    expect(approveRefusal(conflict("plan_frozen_by_moon"), who)).toMatchObject({
      text: "Not approved: Cadence refused this approval. Your approval wasn't recorded.",
      code: "plan_frozen_by_moon",
    });
    expect(approveRefusal({ kind: "unavailable", status: 503, message: "" }, who).unclear).toBe(
      true,
    );
  });
});

describe("submit refusals (U97)", () => {
  const already = (details: unknown) =>
    submitRefusalText(conflict("plan_already_submitted", details), who);
  it("says the plan already waits, with who and when only together", () => {
    const at = "2026-11-19T03:40:00Z";
    expect(already({ submitted_by: { id: "u-mira", name: "Mira K." }, submitted_at: at })).toMatch(
      /^Not sent: R41 was already sent for approval by Mira K\. at (11-19 )?03:40Z, so nothing changed\. Reload to see it\.$/,
    );
    expect(already({ submitted_by: { id: "u-me", name: "Me" }, submitted_at: at })).toMatch(
      /^Not sent: you already sent R41 for approval at (11-19 )?03:40Z, so nothing changed\.$/,
    );
    expect(already({ submitted_by: null, submitted_at: null })).toBe(
      "Not sent: R41 is already waiting for approval, so nothing changed. Reload to see it.",
    );
    expect(submitRefusalText(conflict("duplicate_operation", { plan_id: "p" }), who)).toBe(
      "Not sent: Cadence matched this to an earlier, different request, so nothing changed. Reload and try again.",
    );
  });
});

const plan = { id: "plan_1", version: 41, counts: { passes: 12 } };
const ctx = () => ({
  missionId: missionId("m-1"),
  ops: reviewOps(
    (
      (n) => () =>
        `op-${++n}`
    )(0),
  ),
  userId: "u-me",
  day: "2026-11-16",
});
const submitted = (version: number) => ({
  ok: true as const,
  value: {
    plan_id: "plan_1",
    version,
    state: "pending_approval" as const,
    outcome: "pending_approval" as const,
    replayed: undefined,
    expired: null,
  },
});
const approvedAnswer = (outcome: "approved" | { unrecognized: string }, replayed?: boolean) => ({
  ok: true as const,
  value: { plan_id: "plan_1", state: "executing" as const, outcome, replayed, expired: null },
});

describe("runReview (#257)", () => {
  it("the one act submits, then approves the version submit put up", async () => {
    submit.mockResolvedValue(submitted(42));
    approve.mockResolvedValue(approvedAnswer("approved"));
    const out = await runReview(ctx(), "submit_approve", plan, [], "Checked with ops.");
    expect(out).toMatchObject({
      kind: "after",
      tone: "nominal",
      text: "Approved. Booking 12 passes.",
    });
    expect(submit).toHaveBeenCalledWith(
      expect.anything(),
      { id: "plan_1", version: 41 },
      "op-1",
      [],
      "Checked with ops.",
    );
    expect(approve).toHaveBeenCalledWith(
      expect.anything(),
      { id: "plan_1", version: 42 },
      "op-2",
      [],
      "Checked with ops.",
    );
  });

  it("the one act's submit lands and its approve is refused: the plan waits, and says why (lead)", async () => {
    submit.mockResolvedValue(submitted(42));
    approve.mockResolvedValue({ ok: false, error: conflict("plan_changed") });
    expect(await runReview(ctx(), "submit_approve", plan, [])).toEqual({
      kind: "after",
      tone: "crit",
      text: "R42 was sent for approval, but not approved: it changed after you opened it, so it isn't what you reviewed. It's waiting for approval.",
      because: null,
      expired: null,
    });
    approve.mockResolvedValue({ ok: false, error: self("submitted") });
    expect(await runReview(ctx(), "submit_approve", plan, [])).toMatchObject({
      tone: "crit",
      text: "R42 was sent for approval, but not approved: you submitted this plan, so another org admin approves it. It's waiting for approval.",
      because: "submitted",
    });
  });

  it("a refused submit approves nothing; an unclear approve says so", async () => {
    submit.mockResolvedValue({ ok: false, error: conflict("plan_already_submitted") });
    expect(await runReview(ctx(), "submit_approve", plan, [])).toMatchObject({ kind: "refused" });
    expect(approve).not.toHaveBeenCalled();
    submit.mockResolvedValue(submitted(42));
    approve.mockResolvedValue({
      ok: false,
      error: { kind: "unavailable", status: 502, message: "" },
    });
    const unclear = await runReview(ctx(), "submit_approve", plan, []);
    expect(unclear).toMatchObject({ kind: "after", tone: "caution" });
    expect(unclear.kind === "after" && unclear.text).toMatch(/^Cadence didn't get a clear answer/);
  });

  it("says Approved only on outcome approved, a replay included (U20)", async () => {
    approve.mockResolvedValue(approvedAnswer({ unrecognized: "pending_approval" }));
    expect(await runReview(ctx(), "approve", plan, [])).toMatchObject({
      tone: "caution",
      text: "Cadence didn't record an approval for R41. Reload to see the plan; if it's still waiting, try again or tell the team that runs Cadence for you.",
    });
    approve.mockResolvedValue(approvedAnswer("approved", true));
    expect(await runReview(ctx(), "approve", plan, [])).toMatchObject({
      tone: "nominal",
      text: "Approved. Booking 12 passes.",
    });
    expect(submit).not.toHaveBeenCalled();
  });

  it("an approve-only self refusal closes the sheet with its words; others stay in the sheet", async () => {
    approve.mockResolvedValue({ ok: false, error: self("edited") });
    const own = await runReview(ctx(), "approve", plan, []);
    expect(own).toMatchObject({ kind: "after", tone: "crit", because: "edited" });
    expect(own.kind === "after" && own.text).toMatch(/^Not approved: you drafted this version/);
    approve.mockResolvedValue({ ok: false, error: conflict("plan_changed") });
    expect(await runReview(ctx(), "approve", plan, [])).toMatchObject({ kind: "refused" });
  });

  it("a submit says Sent for approval", async () => {
    submit.mockResolvedValue(submitted(41));
    expect(await runReview(ctx(), "submit", plan, [], "note")).toMatchObject({
      tone: "nominal",
      text: "Sent for approval.",
    });
    expect(approve).not.toHaveBeenCalled();
  });

  it("makes both op ids from one click and reuses them only for the same request (domain 3)", async () => {
    submit.mockResolvedValue({ ok: false, error: { kind: "unavailable", status: 0, message: "" } });
    const c = ctx();
    await runReview(c, "submit_approve", plan, [], "a");
    await runReview(c, "submit_approve", plan, [], "a");
    await runReview(c, "submit_approve", plan, [], "b");
    expect(submit.mock.calls.map((call) => call[2])).toEqual(["op-1", "op-1", "op-3"]);
    expect(c.ops("x")).toEqual({ submit: "op-5", approve: "op-6" });
  });
});
