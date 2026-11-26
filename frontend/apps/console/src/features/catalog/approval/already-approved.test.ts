import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api/index.ts";
import { approvalOps } from "./api.ts";
import { decisionFailure } from "./words.ts";

/** #260 (#613): approving a revision someone already approved, in mms-ux's three lines. */
const already = (details: unknown): ApiError => ({
  kind: "conflict",
  code: "mission_model_revision_already_approved",
  message: "x",
  details,
});
const line = (details: unknown, rev: number | null = 4, viewer: string | null = "u-me") =>
  decisionFailure(already(details), rev, "approve", viewer).text;
const at = "2026-11-20T06:52:00Z";

describe("already approved (#260)", () => {
  it("tells the viewer they approved it themselves", () => {
    expect(line({ decided_by: { id: "u-me", name: "Mira K." }, decided_at: at })).toMatch(
      /^You already approved catalog rev 4 at .+\. Reload to see it\.$/,
    );
  });

  it("names someone else, and says the approval wasn't recorded", () => {
    expect(line({ decided_by: { id: "u-ana", name: "Ana R." }, decided_at: at })).toMatch(
      /^Catalog rev 4 was already approved by Ana R\. at .+, so your approval wasn't recorded\. Reload to see it\.$/,
    );
    // A person no longer a member: id and name null, the time kept; no "by".
    expect(line({ decided_by: { id: null, name: null }, decided_at: at })).toMatch(
      /^Catalog rev 4 was already approved at .+, so your approval wasn't recorded\./,
    );
  });

  it("says it plainly when neither is known, or the details don't read", () => {
    const plain =
      "Not approved: catalog rev 4 was already approved, so your approval wasn't recorded. Reload to see it.";
    expect(line({ decided_by: null, decided_at: null })).toBe(plain);
    expect(line(null)).toBe(plain);
    expect(line({ decided_by: null, decided_at: null }, null)).toBe(
      "Not approved: this catalog revision was already approved, so your approval wasn't recorded. Reload to see it.",
    );
  });

  it("names a composed base 'composition 3' (U109)", () => {
    const composed = (details: unknown) =>
      decisionFailure(already(details), null, "approve", "u-me", "composition 3").text;
    expect(composed({ decided_by: { id: "u-ana", name: "Ana R." }, decided_at: at })).toMatch(
      /^Composition 3 was already approved by Ana R\. at /,
    );
    expect(composed({ decided_by: { id: "u-me", name: "Mira K." }, decided_at: at })).toMatch(
      /^You already approved composition 3 at /,
    );
  });

  it("never treats a missing viewer as the approver", () => {
    expect(line({ decided_by: { id: null, name: null }, decided_at: at }, 4, null)).not.toMatch(
      /^You/,
    );
  });
});

describe("approval operation ids (#260)", () => {
  it("reuses one id for a retry of the same approval, and mints one for another report", () => {
    let n = 0;
    const ops = approvalOps(() => `op-${++n}`);
    expect(ops("mm-1", "rep-1")).toBe("op-1");
    expect(ops("mm-1", "rep-1")).toBe("op-1");
    expect(ops("mm-1", "rep-2")).toBe("op-2");
    expect(ops("mm-2", "rep-2")).toBe("op-3");
  });
});
