import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId } from "@/api/index.ts";
import { actor, showBody } from "./fixtures.ts";
import { decide, decisionSummaryReader } from "./show.ts";

afterEach(() => vi.unstubAllGlobals());

/**
 * #1051 part 4: the decision answer becomes a summary. Synthetic bodies in commanding-eng's shape
 * ({id, state, decision, decided_by, decided_at, review_token}), not captured from a server.
 */
const summary = {
  id: "grp-1",
  state: "queued",
  decision: {
    kind: "go",
    excluded: [],
    note: null,
    members_digest: "d1",
    excluded_request_ids: [],
  },
  decided_by: actor,
  decided_at: "2026-11-27T10:02:00Z",
  review_token: "tok-2",
};

describe("the decision answer (#1051 part 4)", () => {
  it("decodes today's full group read and the summary alike", () => {
    const full = decode(decisionSummaryReader, showBody);
    const small = decode(decisionSummaryReader, summary);
    if (!small.ok) throw new Error(JSON.stringify(small.error));
    expect(full.ok && full.value.review_token).toBe("tok");
    expect(small.ok && [small.value.state, small.value.decision?.kind]).toEqual(["queued", "go"]);
  });

  it("reads a summary-only answer as done", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() =>
        Promise.resolve(new Response(JSON.stringify({ data: summary }), { status: 200 })),
      ),
    );
    const r = await decide(missionId("m-1"), "grp-1", {
      kind: "go",
      excluded: [],
      note: "",
      expectedReview: "tok",
    });
    expect(r.status === "done" && r.value.review_token).toBe("tok-2");
  });
});
