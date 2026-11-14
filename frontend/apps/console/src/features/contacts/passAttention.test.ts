import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { attentionReader } from "@/features/now/index.ts";
import { passAttentionDescription, passAttentionTag } from "./passAttention.ts";

const item = (source: string, conflict: string | null) => {
  const r = decode(attentionReader, {
    id: `${source}-1`,
    source,
    conflict,
    state: "open",
    acknowledged_by: null,
    contact_id: "contact-1",
    station: null,
    provider: null,
    starts_at: null,
    raised_at: "2026-11-14T03:10:00Z",
    provider_message: null,
    resolution: null,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};

describe("pass attention tag (ux U45)", () => {
  it("shows the top item and counts the rest", () => {
    const start = item("contact_start", "not_started");
    const missed = item("contact_start", "missed");
    const change = item("provider_change", "approval_required");
    expect(passAttentionTag({ attention: start, attentions: [start] })).toEqual({
      state: "caution",
      label: "Not started",
      more: 0,
    });
    expect(passAttentionTag({ attention: change, attentions: [change, missed] })).toEqual({
      state: "caution",
      label: "Needs attention",
      more: 1,
    });
    expect(passAttentionTag({ attention: missed, attentions: undefined })?.state).toBe("crit");
    expect(passAttentionTag({ attention: null, attentions: [] })).toBeNull();
  });

  it("says it in words for the bar, without parentheses", () => {
    const missed = item("contact_start", "missed");
    const other = item("pass_resolution", "cancel_failed");
    expect(
      passAttentionDescription({ attention: missed, attentions: [missed, other, other] }),
    ).toBe(", was missed, and 2 more items");
    expect(
      passAttentionDescription({
        attention: item("contact_start", "not_started"),
        attentions: undefined,
      }),
    ).toBe(", hasn't started");
    expect(passAttentionDescription({ attention: other, attentions: [other] })).toBe(
      ", needs attention",
    );
    expect(passAttentionDescription({ attention: null, attentions: [] })).toBe("");
  });
});
