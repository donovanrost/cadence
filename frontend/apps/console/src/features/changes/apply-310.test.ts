import { describe, expect, it } from "vite-plus/test";
import { decode, type ApiError } from "@/api";
import { previewReader, type Preview } from "./actions.ts";
import { cannotApplyLine, noGoReason } from "./apply-reasons.ts";
import { applyRefusal } from "./apply-refusals.ts";

/** #310 (Changes.md K3; ca-ux 11-20, U79): Apply names what stops it, and refusals open "Not applied:". */
function preview(items: readonly unknown[]): Preview {
  const r = decode(previewReader, {
    verdict: "no_go",
    diffs: [],
    checks: [{ key: "validation", verdict: "no_go", items }],
    effects: [],
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}
const refused = (code: string, details: unknown = null, message = "server words"): ApiError => ({
  kind: "conflict",
  code,
  message,
  details,
});

describe("Apply's disabled reasons", () => {
  it("names the NO-GO by its first item, as the checks word it", () => {
    const p = preview([
      {
        kind: "spacecraft",
        entity_id: "sc1",
        sentence: "SCID 312 is already used in this mission.",
      },
    ]);
    expect(noGoReason(p)).toBe("Can't apply yet: SCID 312 is already used in this mission.");
    expect(noGoReason(preview([]))).toBe("Can't apply yet: a check says NO-GO.");
    expect(noGoReason(p, "request_review")).toBe(
      "Can't send for review yet: SCID 312 is already used in this mission.",
    );
  });

  it("says who can apply without the capability, naming no role", () => {
    expect(cannotApplyLine("EARENDIL")).toBe(
      "You can't apply changes on EARENDIL, so someone who can operate it applies them.",
    );
  });
});

describe("apply refusals open 'Not applied:'", () => {
  it("words each known code: why, so nothing changed, what to do", () => {
    expect(applyRefusal(refused("change_set_changed"))?.sentence).toBe(
      "Not applied: someone changed the change set while you were looking, so nothing changed. It's been reloaded; check it, then apply again.",
    );
    expect(applyRefusal(refused("checks_failed"))?.sentence).toBe(
      "Not applied: a check says NO-GO, so nothing changed. Fix the NO-GO items, then apply again.",
    );
    expect(applyRefusal(refused("nothing_staged"))?.sentence).toBe(
      "Not applied: nothing is staged, so there's nothing to apply.",
    );
    expect(applyRefusal(refused("activation_policy_changed"))?.sentence).toBe(
      "Not applied: the mission's approval setting changed while you had this open, so nothing changed. Check whether it now needs review, then apply or send it for review.",
    );
    expect(applyRefusal(refused("holds_blocking"))?.changed).toBe(false);
  });

  it("words Request review's refusals by its act (#553; U79 in #554)", () => {
    expect(applyRefusal(refused("checks_failed"), "request_review")?.sentence).toBe(
      "Not sent for review: a check says NO-GO, so nothing changed. Fix the NO-GO items, then send it for review again.",
    );
    expect(applyRefusal(refused("holds_blocking"), "request_review")?.sentence).toBe(
      "Not sent for review: a blocking hold stands, so nothing changed. It can't be acknowledged; send it for review once it clears (the checks show it).",
    );
    expect(applyRefusal(refused("activation_policy_changed"), "request_review")?.sentence).toBe(
      "Not sent for review: the mission's approval setting changed while you had this open, so nothing changed. Check whether it still needs review, then apply or send it for review.",
    );
    expect(applyRefusal(refused("nothing_staged"), "request_review")?.sentence).toBe(
      "Not sent for review: nothing is staged, so there's nothing to review.",
    );
    expect(applyRefusal(refused("quorum_lost"), "request_review")?.sentence).toBe(
      "Not sent for review: Cadence refused this, so nothing changed.",
    );
    expect(
      applyRefusal(
        {
          kind: "invalid",
          code: "invalid_params",
          message: "x",
          details: { reason: "is too short" },
        },
        "request_review",
      )?.sentence,
    ).toBe(
      "Not sent for review: some changes aren't valid, so nothing changed. Reason: is too short",
    );
  });

  it("lists invalid changes by their field words, never raw paths, up to five", () => {
    const errors = Array.from({ length: 7 }, (_, i) => ({
      path: "display_name",
      message: `bad ${i}`,
    }));
    const r = applyRefusal({
      kind: "invalid",
      code: "invalid_op",
      message: "x",
      details: { index: 0, errors },
    });
    expect(r?.sentence).toMatch(/^Not applied: some changes aren't valid, so nothing changed\. /);
    expect(r?.sentence).toContain("bad 4 · and 2 more");
    expect(r?.sentence).not.toContain("display_name");
  });

  it("never shows the server's text as the line: an unknown code goes to Technical details", () => {
    const r = applyRefusal(refused("quorum_lost", null, "the quorum was lost"));
    expect(r?.sentence).toBe("Not applied: Cadence refused this, so nothing changed.");
    expect(r?.technical).toBe("quorum_lost: the quorum was lost");
  });

  it("leaves to other paths what they already word", () => {
    expect(applyRefusal(refused("in_use"))).toBeNull();
    expect(applyRefusal(refused("mission_model_comparison_failed"))).toBeNull();
    expect(applyRefusal(refused("reason_required"))).toBeNull();
    expect(applyRefusal({ kind: "malformed", message: "x" })).toBeNull();
    expect(applyRefusal({ kind: "unavailable", status: 0, message: "x" })).toBeNull();
  });
});
