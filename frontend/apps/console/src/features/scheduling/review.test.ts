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
      text: "Not approved: you drafted a version of this plan since it was last approved, so another org admin approves it. Your approval wasn't recorded and nothing was booked.",
      because: "edited",
    });
    // #277 (U97, #592): a service identity made a version and no one is accountable for it.
    const authors = (service: unknown) =>
      approveRefusal(forbidden("contact_plan_approver_authors_unknown", { service }), who);
    expect(authors({ id: "svc_1", name: "Nightly planner" }).text).toBe(
      "Not approved: Nightly planner made one of this plan's versions since it was last approved and has no one recorded as accountable for it, so this can't be approved yet. An org admin records who's accountable in People › Service identities. Your approval wasn't recorded. You can also draft the day again so a new plan replaces this one.",
    );
    expect(authors({ id: "svc_1", name: null }).text).toBe(
      "Not approved: a service identity that made one of this plan's versions since it was last approved has no one recorded as accountable for it, so this can't be approved yet. An org admin records who's accountable in People › Service identities. Your approval wasn't recorded. You can also draft the day again so a new plan replaces this one.",
    );
    expect(authors(null).text).toBe(
      "Not approved: Cadence can't tell who made one of this plan's versions since it was last approved, so it can't check that you weren't one of them. Your approval wasn't recorded. Draft the day again so a new plan replaces this one; if it keeps happening, tell the team that runs Cadence for you.",
    );
    expect(authors(null).because).toBeNull();
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

  it("keeps U61's lines and the server's own message as they are (dashboards)", () => {
    expect(approveRefusal(conflict("contact_plan_day_already_planned"), who)).toMatchObject({
      text: "Not approved: another plan already covers this day.",
      reason: "another plan already covers this day",
    });
    const invalid: ApiError = {
      kind: "invalid",
      code: "invalid_params",
      message: "Keep the note under 2,000 characters.",
      details: null,
    };
    expect(approveRefusal(invalid, who).text).toBe(
      "Not approved: Keep the note under 2,000 characters.",
    );
  });

  it("words a changed, missing, foreign or unknown refusal", () => {
    expect(approveRefusal(conflict("plan_changed"), who).text).toBe(
      "Not approved: R41 changed after you opened it, so it isn't what you reviewed. Your approval wasn't recorded. Reload to review it again.",
    );
    expect(
      approveRefusal({ kind: "not_found", code: "plan_not_found", message: "" }, who).text,
    ).toBe(
      "Not approved: Cadence can't find this plan any more, so your approval wasn't recorded. Reload to see 11-16's plans.",
    );
    expect(approveRefusal(forbidden("forbidden"), who).text).toBe(
      "Not approved: only an org admin approves contact plans. Your approval wasn't recorded.",
    );
    expect(approveRefusal(conflict("plan_superseded"), who)).toMatchObject({
      text: "Not approved: contact rules changed after R41 was drafted, so it's superseded and can't be booked. Your approval wasn't recorded. Draft the day again.",
      reason: "it's superseded by newer contact rules",
    });
    expect(approveRefusal(conflict("duplicate_operation", { plan_id: "p" }), who).text).toBe(
      "Not approved: Cadence matched this to an earlier, different request, so your approval wasn't recorded. Reload and try again.",
    );
    expect(approveRefusal({ kind: "unavailable", status: 502, message: "" }, who).text).toBe(
      "Cadence didn't give a clear answer, so your approval may not have been recorded. Reload to see the plan before you try again.",
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

describe("not ready, gaps and partial approval (U97, ux's #257 check)", () => {
  const notReady = (details: unknown): ApiError => ({
    kind: "invalid",
    code: "plan_not_ready",
    message: "x",
    details,
  });
  it("says what blocks the plan: conflicting passes, else uncovered spacecraft, else neither", () => {
    const conflicts = [{ snapshot_ids: ["a", "b"] }, { snapshot_ids: ["b"] }];
    expect(
      approveRefusal(notReady({ conflicts, unmet: [{ spacecraft_id: "sc1" }] }), who),
    ).toMatchObject({
      text: "Not approved: 2 of R41's passes conflict with other bookings, so it can't be booked. Your approval wasn't recorded. Send it back so it can be planned again.",
      reason: "2 of its passes conflict with other bookings",
    });
    const unmet = [{ spacecraft_id: "sc1" }, { spacecraft_id: "sc1" }, { spacecraft_id: "sc2" }];
    expect(approveRefusal(notReady({ conflicts: [], unmet }), who).text).toBe(
      "Not approved: R41 isn't ready to approve: 2 spacecraft aren't covered. Your approval wasn't recorded. Reload to see the gaps.",
    );
    expect(approveRefusal(notReady(null), who).text).toBe(
      "Not approved: R41 isn't ready to approve. Your approval wasn't recorded. Reload to see what's missing.",
    );
  });
  it("counts the gaps that need a reason by spacecraft (U23)", () => {
    const unmet = [
      { requirement_id: "r1", spacecraft_id: "sc1" },
      { requirement_id: "r2", spacecraft_id: "sc1" },
      { requirement_id: "r3", spacecraft_id: "sc2" },
      { requirement_id: "r4", spacecraft_id: "sc3" },
    ];
    const ack = (missing: string[]): ApiError => ({
      kind: "invalid",
      code: "acknowledgements_required",
      message: "x",
      details: { missing },
    });
    expect(approveRefusal(ack(["r1", "r2", "r3"]), { ...who, unmet }).text).toBe(
      "Not approved: 2 gaps need a reason first. Your approval wasn't recorded. Give a reason for each, then approve.",
    );
    expect(approveRefusal(ack(["r4"]), { ...who, unmet }).text).toMatch(
      /^Not approved: 1 gap needs/,
    );
    // ca-ux's #338 review: requirements the loaded plan can't place by spacecraft aren't counted.
    expect(approveRefusal(ack(["r9"]), { ...who, unmet }).text).toBe(
      "Not approved: some gaps need a reason first. Your approval wasn't recorded. Give a reason for each, then approve.",
    );
    expect(approveRefusal(ack([]), who).text).toMatch(
      /^Not approved: some gaps need a reason first/,
    );
  });
});

describe("booking windows closed since the approver looked (#273, #340)", () => {
  const item = (id: string) => ({
    snapshot_id: id,
    spacecraft: null,
    station: null,
    aos: "2026-11-16T00:10:00Z",
    expires_at: "2026-11-15T23:00:00Z",
    reason: "opportunity_expired" as const,
  });
  const set = (ids: string[], count = ids.length) => ({
    count,
    reservable_count: 10,
    items: ids.map(item),
  });
  const changed = (current: unknown): ApiError => ({
    kind: "conflict",
    code: "contact_plan_expired_passes_changed",
    message: "x",
    details: { expired: current, expired_digest: "d2" },
  });
  const shown = set(["a"]);
  it("counts the newly closed passes from two uncapped lists, and lists them", () => {
    const r = approveRefusal(changed(set(["a", "b", "c"])), { ...who, shown });
    expect(r.text).toBe(
      "Not approved: the booking window closed for 2 more of R41's passes after you opened it, so what you'd approve changed. Your approval wasn't recorded. Check the list and approve again.",
    );
    expect(r.reason).toBe("the booking window closed for 2 more of its passes after you opened it");
    expect(r.items?.map((i) => i.snapshot_id)).toEqual(["b", "c"]);
  });
  it("goes countless when either list is capped or can't be diffed (ca-security)", () => {
    const countless =
      "Not approved: the booking window closed for more of R41's passes after you opened it, so what you'd approve changed. Your approval wasn't recorded. Check the list and approve again.";
    expect(approveRefusal(changed(set(["a", "b"], 6_000)), { ...who, shown }).text).toBe(countless);
    expect(
      approveRefusal(changed(set(["a", "b"])), { ...who, shown: set(["a"], 5_001) }).text,
    ).toBe(countless);
    expect(approveRefusal(changed(null), { ...who, shown }).text).toBe(countless);
    expect(approveRefusal(changed(set(["a", "b"])), { ...who, shown }).items).toHaveLength(1);
  });
  it("words Re-plan's proposal as 'Not applied'", () => {
    expect(
      approveRefusal(changed(set(["a", "b", "c"])), { ...who, shown, proposal: true }).text,
    ).toBe(
      "Not applied: the booking window closed for 2 more of the proposal's passes after you opened it, so what you'd apply changed. Nothing was booked. Check the list and apply it again.",
    );
  });
  it("words step 1's interim refusal without a count", () => {
    expect(approveRefusal(conflict("contact_plan_opportunity_expired"), who).text).toBe(
      "Not approved: the booking window has closed for some of R41's passes, so R41 can't be booked as it is. Your approval wasn't recorded. To book the others, draft the day again without them.",
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
  it("the one act submits, then approves the version submit put up; the note goes on the decision only", async () => {
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
      undefined,
    );
    expect(approve).toHaveBeenCalledWith(
      expect.anything(),
      { id: "plan_1", version: 42 },
      "op-2",
      [],
      "Checked with ops.",
      undefined,
    );
  });

  it("the one act's submit lands and its approve is refused: the plan waits, and says why (lead)", async () => {
    submit.mockResolvedValue(submitted(42));
    approve.mockResolvedValue({ ok: false, error: conflict("plan_changed") });
    expect(await runReview(ctx(), "submit_approve", plan, [], "Checked.")).toEqual({
      kind: "after",
      tone: "crit",
      text: "R42 was sent for approval, but not approved: it changed after you opened it, so it isn't what you reviewed. It's waiting for approval.",
      version: 42,
      because: null,
      expired: null,
      keepNote: "Checked.",
    });
    approve.mockResolvedValue({ ok: false, error: self("submitted") });
    expect(await runReview(ctx(), "submit_approve", plan, [])).toMatchObject({
      tone: "crit",
      text: "R42 was sent for approval, but not approved: you submitted this plan, so another org admin approves it. It's waiting for approval.",
      because: "submitted",
    });
  });

  it("the one act's partial line uses U97's explicit reasons", async () => {
    submit.mockResolvedValue(submitted(42));
    approve.mockResolvedValue({
      ok: false,
      error: conflict("duplicate_operation", { plan_id: "p" }),
    });
    expect(await runReview(ctx(), "submit_approve", plan, [])).toMatchObject({
      text: "R42 was sent for approval, but not approved: Cadence matched it to an earlier, different request. It's waiting for approval.",
    });
    approve.mockResolvedValue({
      ok: false,
      error: { kind: "not_found", code: "plan_not_found", message: "" },
    });
    expect(await runReview(ctx(), "submit_approve", plan, [])).toMatchObject({
      tone: "crit",
      text: "R42 was sent for approval, but Cadence can't find it any more. Reload to see 11-16's plans.",
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
    expect(unclear.kind === "after" && unclear.text).toBe(
      "R42 was sent for approval, but Cadence didn't give a clear answer about the approval. Reload to see whether it was recorded before you try again.",
    );
  });

  it("counts the passes an approval left out from the answer (U61, #273)", async () => {
    const expired = { count: 3, reservable_count: 9, items: [] };
    approve.mockResolvedValue({
      ok: true,
      value: { ...approvedAnswer("approved").value, expired },
    });
    expect(await runReview(ctx(), "approve", plan, [])).toMatchObject({
      tone: "nominal",
      text: "Approved. Booking 9 passes; 3 weren't booked because their booking window had closed.",
      expired,
    });
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
    expect(own.kind === "after" && own.text).toMatch(
      /^Not approved: you drafted a version of this plan/,
    );
    approve.mockResolvedValue({ ok: false, error: conflict("plan_changed") });
    expect(await runReview(ctx(), "approve", plan, [])).toMatchObject({ kind: "refused" });
  });

  it("a submit says Sent only on outcome pending_approval; anything else stops the one act (U20)", async () => {
    submit.mockResolvedValue({
      ok: true,
      value: { ...submitted(42).value, outcome: { unrecognized: "accepted" } },
    });
    expect(await runReview(ctx(), "submit_approve", plan, [])).toMatchObject({
      tone: "caution",
      text: "Cadence didn't confirm that R42 was sent for approval. Reload to see the plan.",
    });
    expect(approve).not.toHaveBeenCalled();
  });

  it("a submit says Sent for approval, with its note", async () => {
    submit.mockResolvedValue(submitted(41));
    expect(await runReview(ctx(), "submit", plan, [], "note")).toMatchObject({
      tone: "nominal",
      text: "Sent for approval.",
    });
    expect(submit.mock.calls[0]?.[4]).toBe("note");
    expect(approve).not.toHaveBeenCalled();
  });

  it("sends the read's expired_digest on approve, and a new digest is a new request (#273)", async () => {
    approve.mockResolvedValue(approvedAnswer("approved"));
    const c = ctx();
    await runReview(c, "approve", { ...plan, expired_digest: "d1" }, []);
    await runReview(c, "approve", { ...plan, expired_digest: "d1" }, []);
    await runReview(c, "approve", { ...plan, expired_digest: "d2" }, []);
    expect(approve.mock.calls.map((call) => [call[2], call[5]])).toEqual([
      ["op-2", "d1"],
      ["op-2", "d1"],
      ["op-4", "d2"],
    ]);
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
