import { describe, expect, it } from "vite-plus/test";
import { buildDraft } from "./compose/draft.ts";
import { memberStageWord } from "./groups/words.ts";
import { expiresWords, expiryProblem, priorityChoices, priorityTag } from "./priority.ts";

describe("priority words (ux U68)", () => {
  it("Normal is silent; below reads HIGH PRIORITY, above LOW PRIORITY", () => {
    expect(priorityTag(3)).toBeNull();
    expect(priorityTag(null)).toBeNull();
    expect(priorityTag(1)).toBe("HIGH PRIORITY");
    expect(priorityTag(0)).toBe("HIGH PRIORITY");
    expect(priorityTag(7)).toBe("LOW PRIORITY");
  });
  it("offers Normal · High, and keeps a resend's low one as 'Low (as before)'", () => {
    expect(priorityChoices(3).map((c) => c.label)).toEqual(["Normal", "High"]);
    expect(priorityChoices(1).map((c) => c.label)).toEqual(["Normal", "High"]);
    expect(priorityChoices(6)).toEqual([
      { value: "3", label: "Normal" },
      { value: "1", label: "High" },
      { value: "6", label: "Low (as before)" },
    ]);
  });
});

describe("expiry (ux U68)", () => {
  const now = Date.parse("2026-11-16T01:00:00Z");
  it("refuses a past time, and one not after the hold", () => {
    expect(expiryProblem(null, null, now)).toBeNull();
    expect(expiryProblem(now - 1, null, now)).toBe("Pick a time in the future.");
    expect(
      expiryProblem(Date.parse("2026-11-16T02:00:00Z"), Date.parse("2026-11-16T02:00:00Z"), now),
    ).toBe("Pick a time after the hold time, 11-16 02:00Z.");
    expect(expiryProblem(Date.parse("2026-11-16T04:00:00Z"), null, now)).toBeNull();
  });
  it("words the expiry and an expired member", () => {
    expect(expiresWords("2026-11-16T04:00:00Z")).toBe("Expires 11-16 04:00Z");
    expect(memberStageWord("canceled", "queued", "expired", null, "2026-11-16T04:00:00Z")).toBe(
      "Expired at 04:00Z before it was released",
    );
  });
  it("sends expires_at and the priority", () => {
    const d = buildDraft({
      title: "t",
      log: "",
      targets: [],
      query: { plane: null, profile: null, states: [], explicit: [] },
      stack: [],
      notBefore: null,
      expiresAt: Date.parse("2026-11-16T04:00:00Z"),
      priority: 1,
      approver: "",
      sentBackFrom: null,
      endpoints: {},
    });
    expect(d?.expires_at).toBe("2026-11-16T04:00:00.000Z");
    expect(d?.priority).toBe(1);
  });
});
