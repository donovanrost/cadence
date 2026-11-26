/** GET /config fixtures for spacecraft screens' staging tests. */
const actor = { kind: "user", id: "u1", name: "Mira K." };
/** GET /config with the open set holding the given ops. */
export const configWith = (ops: readonly Record<string, unknown>[]) => ({
  head: {
    revision: 5,
    kind: "change_set",
    live: true,
    applied_at: "2026-11-16T02:29:00Z",
    applied_by: actor,
    reason: "r5",
    summary: null,
    entry_count: 1,
    change_set_id: null,
    rolls_back_to: null,
    approvals: [],
  },
  change_set: {
    id: "cs-1",
    version: 1,
    state: "open",
    base_revision: 5,
    opened_at: "2026-11-16T21:00:00Z",
    opened_by: actor,
    staged_count: 1,
    changes: [
      {
        id: "c-1",
        summary: "Turn commanding off · EARENDIL-312",
        author: actor,
        staged_at: "2026-11-16T21:00:00Z",
        source: { surface: "spacecraft" },
        state: "staged",
        ops: ops.map((o, i) => ({ id: `o-${i}`, paths: [], payload: null, ...o })),
      },
    ],
    withdrawn: [],
    authors: [actor],
    submitted_by: null,
    submitted_at: null,
    reason: null,
    approval_required: null,
    reviews: [],
    failure: null,
    applied_revision: null,
  },
  permissions: ["config.stage"],
});
