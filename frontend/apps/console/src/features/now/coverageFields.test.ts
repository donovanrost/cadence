import { describe, expect, it } from "vite-plus/test";
import { attentionReader } from "./attention.ts";

const item = (extra: Record<string, unknown>) => ({
  id: "2026-11-16",
  source: "plan_coverage",
  conflict: null,
  state: "open",
  acknowledged_by: null,
  contact_id: null,
  station: null,
  provider: null,
  starts_at: null,
  raised_at: "2026-11-15T00:28:00Z",
  provider_message: null,
  resolution: null,
  ...extra,
});

describe("plan_coverage (U61)", () => {
  it("reads the day, its newest plan (sent back = draft + sent_back), and the approvers", () => {
    const a = attentionReader(
      item({
        day: "2026-11-16",
        first_window_at: "2026-11-16T00:28:49Z",
        due_at: "2026-11-16T00:28:49Z",
        severity: "caution",
        requirements_count: 1512,
        open_requirements_count: 1104,
        plan: {
          id: "contact_plan_41",
          revision: 41,
          state: "draft",
          author: { id: "user_m", name: "Mira K." },
          submitted_at: "2026-11-11T22:10:00Z",
          sent_back: {
            by: { id: "user_a", name: "Ana R." },
            at: "2026-11-12T09:40:00Z",
            comment: "Too many KSAT passes.",
          },
        },
        approvers: [{ id: "user_a", name: "Ana R." }],
        viewer_can_approve: false,
      }),
    );
    expect(a.source).toBe("plan_coverage");
    expect(a.plan?.state).toBe("draft");
    expect(a.plan?.sent_back?.by?.name).toBe("Ana R.");
    expect(a.severity).toBe("caution");
    expect(a.approvers?.map((p) => p.name)).toEqual(["Ana R."]);
  });

  it("keeps an unknown plan state's text, and reads a day with no plan", () => {
    const later = attentionReader(
      item({
        plan: {
          id: "p",
          revision: 2,
          state: "approved_pending_booking",
          author: null,
          submitted_at: null,
          sent_back: null,
        },
      }),
    );
    expect(later.plan?.state).toEqual({ unrecognized: "approved_pending_booking" });
    const none = attentionReader(item({ plan: null }));
    expect(none.plan).toBeNull();
    expect(attentionReader(item({})).plan).toBeUndefined();
  });
});
