import { describe, expect, it } from "vite-plus/test";
import type { ResolutionAction } from "./attention.ts";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { resolvedWords } from "./attention.ts";
import { NO_ACCESS_ARCHIVE, discardTitle } from "./archive.ts";
import { noAccessText } from "./useQueueCommand.ts";

const NOW = new Date("2026-11-14T03:16:00Z");

/** The queue item as api serves it (domain + api shape 11-14). */
const item = (o: Record<string, unknown> = {}, priority = 2) => ({
  id: "attention:archive_quarantine:rc-8:identity_conflict",
  priority,
  kind: "attention",
  state: "caution",
  source: "archive_quarantine",
  acknowledged: null,
  since: "2026-11-14T03:10:00Z",
  due_at: null,
  count: 1,
  spacecraft: [
    {
      id: "spacecraft-earendil-008",
      name: "EARENDIL-008",
      scid: 8,
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
    id: "rc-8:identity_conflict",
    source: "archive_quarantine",
    conflict: "quarantined",
    state: "open",
    acknowledged_by: null,
    contact_id: "contact-8",
    reservation_id: "pass-8",
    station: { ref: "svb", id: "st-2", code: "SVB", name: "Svalbard B" },
    provider: { id: "p-1", name: "Northlight" },
    starts_at: "2026-11-14T03:10:00Z",
    ends_at: "2026-11-14T03:15:50Z",
    raised_at: "2026-11-14T03:14:02Z",
    provider_message: null,
    expires_at: null,
    realized_contact_id: "rc-8",
    spacecraft_id: "spacecraft-earendil-008",
    error_code: "identity_conflict",
    error: "conflicting record for {scid: 8, vcid: 0, seq: 4411}",
    counts: { frames: 12, packets: 40 },
    stored_without_archive: { frames: 12, packets: 40 },
    first_received_at: "2026-11-14T03:14:02Z",
    last_received_at: "2026-11-14T03:15:40Z",
    last_seen_at: "2026-11-14T03:12:30Z",
    actions: ["retry", "discard"],
    last_retry: null,
    resolution: null,
    ...o,
  },
});

const rowOf = (o: Record<string, unknown> = {}, priority = 2) => {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
    items: [item(o, priority)],
  });
  if (!r.ok) throw new Error(r.error.message);
  return presentQueue(r.value, NOW, "EARENDIL")[0];
};

describe("archive_quarantine on Now (ux U49)", () => {
  it("names the pass and the counts, says why, what was stored, and the choice", () => {
    const row = rowOf();
    expect(row?.priority).toBe(2);
    expect(row?.title).toBe(
      "EARENDIL-008 · SVB 03:10Z pass · 12 frames and 40 packets couldn't be archived",
    );
    expect(row?.sentence).toBe(
      "The archive already holds different records with the same identity, so these weren't added. Their telemetry was still stored: 12 frames and 40 packets, without an archived copy of the raw records. Retry once the cause is fixed, or discard them if they can't be archived.",
    );
    expect(row?.meta).toBe("12 FRAMES · 40 PACKETS · 03:14Z–03:15Z");
    expect(row?.due).toBeUndefined();
    expect(row?.command?.label).toBe("Retry");
    expect(row?.command?.kind).toBe("retry");
    expect(row?.discard?.id).toBe("rc-8:identity_conflict");
    expect(row?.action.to).toEqual({ name: "ops.contacts", query: { contact: "pass-8" } });
    expect(noAccessText("retry", row?.command?.targets ?? [])).toBe(NO_ACCESS_ARCHIVE);
  });

  it("drops a zero count, uses singulars, and words each cause", () => {
    const row = rowOf({
      counts: { frames: 1, packets: 0 },
      stored_without_archive: { frames: 0, packets: 0 },
      error_code: "data_rejected",
    });
    expect(row?.title).toBe("EARENDIL-008 · SVB 03:10Z pass · 1 frame couldn't be archived");
    expect(row?.meta).toBe("1 FRAME · 03:14Z–03:15Z");
    expect(row?.sentence).toMatch(
      /^The archive rejected their data, so these weren't added\. None of their telemetry was stored\./,
    );
    expect(rowOf({ error_code: "unknown" })?.sentence).toMatch(/^The archive couldn't take them\./);
    expect(rowOf({ error_code: "something_new" })?.sentence).toMatch(
      /^The archive couldn't take them\./,
    );
  });

  it("says STILL ARRIVING while the pass is on and one came in the last 5 minutes", () => {
    const live = { ends_at: "2026-11-14T03:30:00Z", last_seen_at: "2026-11-14T03:15:40Z" };
    expect(rowOf(live)?.meta).toBe("12 FRAMES · 40 PACKETS · 03:14Z–03:15Z · STILL ARRIVING");
    expect(rowOf({ ...live, last_seen_at: "2026-11-14T03:05:00Z" })?.meta).not.toContain("STILL");
  });

  it("titles a contact with no pass, or the count alone with nothing to name", () => {
    expect(rowOf({ reservation_id: null })?.title).toBe(
      "EARENDIL-008 · SVB contact · 12 frames and 40 packets couldn't be archived",
    );
    expect(
      rowOf({ reservation_id: null, station: { ref: null, id: null, code: null, name: null } })
        ?.title,
    ).toBe("EARENDIL-008 · 12 frames and 40 packets couldn't be archived");
    const bare = rowOf({ reservation_id: null, station: null });
    expect(bare?.title).toBe("EARENDIL-008 · 12 frames and 40 packets couldn't be archived");
  });

  it("after a retry that left some, says who retried and how it went", () => {
    const by = { kind: "user", id: "u-1", name: "Mira K." };
    expect(rowOf({ last_retry: { by, at: "2026-11-14T03:20:00Z", indexed: 4 } })?.sentence).toMatch(
      /Retried by Mira K\. at 03:20Z; the rest still couldn't be archived\.$/,
    );
    expect(rowOf({ last_retry: { by, at: "2026-11-14T03:20:00Z", indexed: 0 } })?.sentence).toMatch(
      /Retried by Mira K\. at 03:20Z; none could be archived yet\.$/,
    );
  });

  it("offers only what the server lists, and nothing once resolved", () => {
    const row = rowOf({ actions: ["discard"] });
    expect(row?.command).toBeUndefined();
    expect(row?.discard).toBeDefined();
    const done = rowOf({
      state: "resolved",
      resolution: {
        action: "discarded",
        actor: { kind: "user", id: "u-1", name: "Mira K." },
        at: "2026-11-14T03:22:00Z",
        note: "Duplicate replay of yesterday's pass.",
        provider_reference: null,
      },
    });
    expect(done?.sentence).toBe(
      "Discarded by Mira K. at 03:22Z: Duplicate replay of yesterday's pass.",
    );
    expect(done?.command).toBeUndefined();
    expect(done?.discard).toBeUndefined();
  });

  it("titles the discard sheet and says how it closed", () => {
    const row = rowOf();
    if (!row?.discard) throw new Error("no discard");
    expect(discardTitle(row.discard)).toBe(
      "Discard 12 frames and 40 packets that couldn't be archived?",
    );
    const closed = (action: ResolutionAction, note: string | null) =>
      resolvedWords(
        {
          id: "attention:archive_quarantine:rc-8:identity_conflict",
          resolved_by: {
            kind: action === "retried" ? "system" : "user",
            id: null,
            name: "Mira K.",
          },
          action,
          resolved_at: "2026-11-14T03:21:00Z",
          note,
        },
        NOW,
      );
    expect(closed("retried", null)).toBe("Archived on retry at 03:21Z.");
    expect(closed("discarded", "Bad replay.")).toBe("Discarded by Mira K. at 03:21Z: Bad replay.");
  });
});
