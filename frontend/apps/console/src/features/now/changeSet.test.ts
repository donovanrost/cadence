import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { authorWords, changeSetWords, type ChangeSet } from "./changeSet.ts";

const now = new Date("2026-11-13T00:00:00Z");
const author = (name: string | null) => ({ kind: "user" as const, id: `u-${name}`, name });
const cs = (over: Partial<ChangeSet> = {}): ChangeSet => ({
  id: "cs-1",
  state: "open",
  staged_count: 3,
  base_revision: 6,
  opened_at: "2026-11-11T01:00:00Z",
  oldest_staged_at: "2026-11-11T02:10:00Z",
  submitted_at: null,
  authors: [author("Mira K."), author("Ana P.")],
  ...over,
});

describe("U39 change_set_stale", () => {
  it("leads with the count; the time belongs to the oldest", () => {
    expect(changeSetWords(cs(), now)).toEqual({
      title: "3 staged changes aren't applied",
      evidence: "Staged on r6 by Mira K. and Ana P. The oldest has waited since 11-11 02:10Z.",
    });
    expect(changeSetWords(cs({ staged_count: 1, authors: [author("Mira K.")] }), now).title).toBe(
      "1 staged change isn't applied",
    );
    expect(
      changeSetWords(cs({ state: "in_review", submitted_at: "2026-11-12T09:00:00Z" }), now),
    ).toEqual({
      title: "3 staged changes are waiting for review",
      evidence: "Sent for review at 11-12 09:00Z. Staged on r6 by Mira K. and Ana P.",
    });
    expect(
      authorWords([
        author("Mira K."),
        author("Ana P."),
        author("Li W."),
        author(null),
        author("Jo"),
      ]),
    ).toBe("Mira K., Ana P. and 2 others");
  });

  it("reads the queue item; an unreadable change_set drops only its row", () => {
    const item = (change_set: unknown) => ({
      id: "change_set_stale:cs-1",
      priority: 3,
      kind: "change_set_stale",
      state: "off",
      source: null,
      acknowledged: null,
      since: "2026-11-11T02:10:00Z",
      due_at: null,
      count: 3,
      spacecraft: [],
      point: null,
      condition: null,
      plane: null,
      command: null,
      outcome: null,
      command_requests: [],
      finding: null,
      change_set,
    });
    const raw = {
      observed_at: "2026-11-13T00:00:00Z",
      counts: { p1: 0, p2: 0, p3: 1, spacecraft_p1: 0 },
      items: [item(cs()), item({ id: "x" })],
    };
    const r = decode(actionQueueReader, raw);
    if (!r.ok) throw new Error(r.error.message);
    const rows = presentQueue(r.value, now);
    expect(rows.map((q) => [q.title, q.meta, q.action.label, q.state])).toEqual([
      ["3 staged changes aren't applied", "SINCE 11-11 02:10Z", "Review", "off"],
    ]);
  });
});
