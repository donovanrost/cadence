import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { resolvedReader, resolvedWords } from "./attention.ts";
import { scidMismatchRow } from "./scidMismatch.ts";
import { noAccessText, NO_ACCESS_SCID } from "./useQueueCommand.ts";

const NOW = new Date("2026-11-14T05:00:00Z");

/** The queue item as api serves it (api 11-16, U81 §2). */
const item = (o: Record<string, unknown> = {}) => ({
  id: "attention:contact_scid_mismatch:rc-9",
  priority: 2,
  kind: "attention",
  state: "caution",
  source: "contact_scid_mismatch",
  acknowledged: null,
  since: "2026-11-14T04:12:00Z",
  due_at: "2026-11-14T03:10:00Z",
  count: 1,
  spacecraft: [
    {
      id: "spacecraft-earendil-312",
      name: "EARENDIL-312",
      scid: 1,
      plane: 3,
      stale: false,
      last_received_at: null,
      violating_points: null,
      value: null,
      first_crossed_at: null,
      episode_id: null,
      status: null,
      assignee: null,
      acknowledged_by: null,
    },
  ],
  point: null,
  condition: null,
  plane: null,
  command: null,
  outcome: null,
  command_requests: [],
  finding: null,
  attention: {
    id: "rc-9",
    source: "contact_scid_mismatch",
    conflict: null,
    state: "open",
    acknowledged_by: null,
    contact_id: "sc-4",
    realized_contact_id: "rc-9",
    reservation_id: "pass-4",
    station: { ref: "fbk", id: "gs-fbk", code: "FBK", name: "Fairbanks" },
    provider: null,
    starts_at: "2026-11-14T03:10:00Z",
    raised_at: "2026-11-14T04:12:00Z",
    provider_message: null,
    spacecraft: { id: "spacecraft-earendil-312", name: "EARENDIL-312", scid: 1 },
    scid_mismatch: { expected_scid: 1, frames: 412, frames_total: 430, scids: [3], scid_count: 1 },
    resolution: null,
    ...o,
  },
});

const rowOf = (o: Record<string, unknown> = {}) => {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
    items: [item(o)],
  });
  if (!r.ok) throw new Error(r.error.message);
  return presentQueue(r.value, NOW, "EARENDIL")[0];
};
const mismatch = (o: Record<string, unknown>) => ({
  scid_mismatch: {
    expected_scid: 1,
    frames: 412,
    frames_total: 430,
    scids: [3],
    scid_count: 1,
    ...o,
  },
});
const TAIL = "Cadence kept them as raw evidence and made no telemetry from them.";

describe("contact_scid_mismatch on Now (ux U81 §2)", () => {
  it("names the pass, says how many frames carried which SCID, and nothing is due", () => {
    const row = rowOf();
    expect(row?.title).toBe(
      "EARENDIL-312 · Most frames on the FBK 03:10Z pass carried another SCID",
    );
    expect(row?.sentence).toBe(
      `412 of 430 frames carried SCID 3, not EARENDIL-312's SCID 1. ${TAIL}`,
    );
    expect(row?.meta).toBe("FBK 03:10Z · SETTLED 04:12Z");
    expect(row?.due).toBeUndefined();
    expect(row?.action).toEqual({
      label: "Open contact record",
      to: { name: "ops.contacts.history", query: { contact: "sc-4" } },
    });
    expect(row?.command?.label).toBe("Mark as seen");
    expect(row?.command?.kind).toBe("seen");
  });

  it("a hand-started contact opens its realized record", () => {
    expect(rowOf({ contact_id: null, reservation_id: null })?.action?.to).toEqual({
      name: "ops.contacts.history",
      query: { contact: "rc-9" },
    });
  });

  it("follows the SCID list rules: complete below 8, else at least the count", () => {
    const s = (o: Record<string, unknown>) => rowOf(mismatch(o))?.sentence;
    expect(s({ scids: [3, 7], scid_count: 2 })).toContain("carried SCIDs 3 and 7, not");
    expect(s({ scids: [3, 7, 9], scid_count: 3 })).toContain("carried SCIDs 3, 7 and 9, not");
    expect(s({ scids: [2, 3, 7, 9], scid_count: 4 })).toContain("carried 4 different SCIDs, not");
    expect(s({ scids: [1, 2, 3, 4, 5, 6, 7, 8], scid_count: 8 })).toContain(
      "carried at least 8 different SCIDs, not",
    );
    expect(s({ scids: [3, 7], scid_count: 5 })).toContain("carried at least 5 different SCIDs");
    expect(s({ frames: 1, frames_total: 1 })).toBe(
      "1 of 1 frame carried SCID 3, not EARENDIL-312's SCID 1. Cadence kept it as raw evidence and made no telemetry from it.",
    );
  });

  it("without a name or a station, never an id", () => {
    const row = rowOf({ spacecraft: { id: "spacecraft-x", name: null, scid: 1 }, station: null });
    // The queue row's own member still names the craft; without both, the title drops it.
    expect(row?.sentence).toContain("not EARENDIL-312's SCID 1");
    const bare = presentBare();
    expect(bare?.title).toBe("Most frames on the 03:10Z pass carried another SCID");
    expect(bare?.sentence).toContain("not this pass's SCID 1.");
    expect(`${bare?.title} ${bare?.sentence} ${bare?.meta}`).not.toMatch(/spacecraft-|rc-9|sc-4/);
    expect(bare?.meta).toBe("03:10Z · SETTLED 04:12Z");
  });

  it("closes as seen (the person, else just the time) or retired unseen, never as seen by someone", () => {
    const words = (o: Record<string, unknown>) => {
      const r = decode(resolvedReader, {
        id: "attention:contact_scid_mismatch:rc-9",
        resolved_at: "2026-11-14T04:20:00Z",
        ...o,
      });
      if (!r.ok) throw new Error(r.error.message);
      return resolvedWords(r.value, NOW);
    };
    expect(
      words({ action: "seen", resolved_by: { kind: "user", id: "u-1", name: "Mira K." } }),
    ).toBe("Seen by Mira K. at 04:20Z.");
    expect(words({ action: "seen", resolved_by: { kind: "user", id: "u-1", name: null } })).toBe(
      "Seen at 04:20Z.",
    );
    expect(
      words({ action: "retired", resolved_by: { kind: "system", id: null, name: null } }),
    ).toBe("Retired after 7 days without being seen.");
  });

  it("an operator without access reads this source's own words", () => {
    const r = decode(actionQueueReader, {
      observed_at: NOW.toISOString(),
      counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
      items: [item()],
    });
    if (!r.ok) throw new Error(r.error.message);
    const a = r.value.items[0]?.attention;
    expect(a && noAccessText("seen", [a])).toBe(NO_ACCESS_SCID);
  });
});

/** No craft name on the attention or the queue member, and no station. */
function presentBare() {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
    items: [item({ spacecraft: { id: "spacecraft-x", name: null, scid: 1 }, station: null })],
  });
  if (!r.ok) throw new Error(r.error.message);
  const a = r.value.items[0]?.attention;
  if (!a) throw new Error("no attention");
  return scidMismatchRow({ priority: 2, state: "caution", spacecraftIds: [] }, "k", a, null, NOW);
}
