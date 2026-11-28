/**
 * GET …/config for gate tests (#1160): an applied head, no open change set, and the viewer's
 * permissions as the server computes them (`config.stage` is `Configuration.Access` `:stage`).
 */
export const configState = (permissions: readonly string[]) => ({
  head: {
    revision: 5,
    kind: "change_set",
    live: true,
    applied_at: "2026-11-16T02:29:00Z",
    applied_by: { kind: "user", id: "u1", name: "Mira K." },
    reason: "r5",
    summary: null,
    entry_count: 1,
    change_set_id: null,
    rolls_back_to: null,
    approvals: [],
  },
  change_set: null,
  permissions,
});

/**
 * A `fetch` that answers by path (`/api/v1` dropped), 404 for anything else; stub it with
 * `vi.stubGlobal("fetch", answerByPath(…))`. `routes` values are the answer's `data`.
 */
export const answerByPath =
  (routes: Readonly<Record<string, unknown>>) =>
  (input: string): Promise<Response> => {
    const path = new URL(input, "http://x").pathname.replace(/^\/api\/v1/, "");
    const data = routes[path];
    return Promise.resolve(
      data === undefined
        ? new Response(JSON.stringify({ error: { code: "not_found" } }), { status: 404 })
        : new Response(JSON.stringify({ data }), { status: 200 }),
    );
  };
