import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";

/** U109 (E2, #546; ca-engineer's shape 11-20): Now's row for a craft on a withdrawn composition. */
const craft = {
  id: "spacecraft-earendil-004",
  name: "EARENDIL-004",
  scid: 4,
  plane: 13,
  stale: false,
  last_received_at: null,
  violating_points: null,
  value: null,
  first_crossed_at: null,
  episode_id: null,
  status: null,
  assignee: null,
  acknowledged_by: null,
};
const withdrawal = (extra: Record<string, unknown> = {}) => ({
  revision_id: "rev-4",
  catalog_revision: { id: "rev-4", number: 4, label: null, database_id: "db-1" },
  kind: "withdrawn",
  decided_by: { id: "u-ana", name: "Ana R." },
  decided_at: "2026-11-20T09:12:00Z",
  reason: "Bad limits",
  composition: null,
  ...extra,
});
const item = (w: Record<string, unknown>, state = "critical") => ({
  id: "attention:model_approval_withdrawn:sc-4",
  priority: state === "critical" ? 1 : 2,
  kind: "attention",
  state,
  source: null,
  acknowledged: null,
  since: "2026-11-20T09:12:00Z",
  due_at: null,
  count: 1,
  spacecraft: [craft],
  point: null,
  condition: null,
  plane: null,
  command: null,
  outcome: null,
  command_requests: [],
  finding: null,
  attention: {
    id: "aw-1",
    source: "model_approval_withdrawn",
    conflict: null,
    state: "open",
    acknowledged_by: null,
    contact_id: null,
    station: null,
    provider: null,
    starts_at: null,
    raised_at: "2026-11-20T09:12:00Z",
    provider_message: null,
    // The keys every attention row carries (AttentionItems), null here.
    resolution: null,
    withdrawal: w,
  },
});
const rows = (items: unknown[]) => {
  const r = decode(actionQueueReader, {
    observed_at: "2026-11-20T09:20:00Z",
    counts: { p1: 1, p2: 0, p3: 0, spacecraft_p1: 1 },
    items,
  });
  if (!r.ok) throw r.error;
  return presentQueue(r.value);
};

describe("model_approval_withdrawn row (U109)", () => {
  it("names the craft and its composition, the decision and no way out before D3", () => {
    const [row] = rows([item(withdrawal())]);
    expect(row?.title).toBe("EARENDIL-004 · On catalog rev 4, which is no longer approved.");
    expect(row?.sentence).toBe("Approval withdrawn by Ana R. at 11-20 09:12Z: “Bad limits”.");
    expect(row?.action).toEqual({
      label: "Open EARENDIL-004",
      to: { name: "ops.spacecraft", params: { scId: 4, tab: "investigate" } },
    });
    expect(row?.priority).toBe(1);
  });

  it("adds the way out once D3 says what's left", () => {
    const earlier = { revision_id: "rev-3", catalog_revision: null };
    expect(rows([item(withdrawal({ earlier_approved: earlier }))])[0]?.sentence).toBe(
      "Approval withdrawn by Ana R. at 11-20 09:12Z: “Bad limits”. Stage a new configuration to move it to catalog rev 4's earlier approved version.",
    );
    expect(rows([item(withdrawal({ earlier_approved: null }), "caution")])[0]?.sentence).toBe(
      "Approval withdrawn by Ana R. at 11-20 09:12Z: “Bad limits”. Move it to an approved composition.",
    );
  });

  it("rejected, nameless and reasonless forms", () => {
    const line = (x: Record<string, unknown>) => rows([item(withdrawal(x))])[0]?.sentence;
    expect(line({ kind: "rejected" })).toBe("Rejected by Ana R. at 11-20 09:12Z: “Bad limits”.");
    expect(line({ decided_by: null, reason: null })).toBe("Approval withdrawn at 11-20 09:12Z.");
  });
});
