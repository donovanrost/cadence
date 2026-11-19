import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { actionQueueReader } from "./actionQueue.ts";
import { attentionReader, resolvedReader, resolvedWords, settlementEvidence } from "./attention.ts";

const NOW = new Date("2026-11-17T05:00:00Z");

/** api's proposed replay_conflict item (11-17, U84), on the storage path while dropping. */
const stuck = (o: Record<string, unknown> = {}) => ({
  id: "rcf-1",
  source: "replay_conflict",
  conflict: "replay_id_conflict",
  state: "open",
  acknowledged_by: { kind: "user", id: "u-1", name: "Mira K." },
  contact_id: null,
  station: null,
  provider: null,
  starts_at: null,
  raised_at: "2026-11-17T03:10:00Z",
  provider_message: null,
  resolution: null,
  path: "storage",
  effect_kind: "alarm_effect",
  effect_id: "eff:3f2a",
  effect_count: 1,
  partition_id: null,
  partition_stopped: false,
  realized_contact_id: "rc-7",
  path_id: "path-2",
  stream_key: "sva-1 / downlink 0",
  contact: { id: "sc-7", station_code: "SVA", starts_at: "2026-11-17T02:49:00Z" },
  affected_spacecraft: [
    { id: "spacecraft-earendil-001", name: "EARENDIL-001", scid: 1 },
    { id: "spacecraft-x", name: null, scid: null },
  ],
  spacecraft_ids: ["spacecraft-earendil-001", "spacecraft-x"],
  spacecraft_count: 2,
  first_seen_at: "2026-11-17T03:10:00Z",
  last_seen_at: "2026-11-17T03:52:00Z",
  occurrences: 14,
  buffer: { used_bytes: 8_600_000_000, max_bytes: 8_600_000_000 },
  dropping: true,
  dropping_since: "2026-11-17T04:40:00Z",
  acknowledged_at: "2026-11-17T03:20:00Z",
  acknowledged_note: "told domain at 03:18Z",
  reraised: true,
  ...o,
});

/** A settled pass whose stored failure is this conflict (U84 cause tag, U37 words). */
const settlement = {
  id: "set-1",
  source: "contact_settlement",
  conflict: "unsettled",
  state: "open",
  acknowledged_by: null,
  contact_id: "sc-7",
  station: null,
  provider: null,
  starts_at: "2026-11-17T02:49:00Z",
  raised_at: "2026-11-17T03:30:00Z",
  provider_message: null,
  resolution: null,
  backlog: { entries: 1204, bytes: 3_400_000, journals: 1 },
  failure_kind: "replay_id_conflict",
  retry: "automatic",
  stuck_processing_id: "rcf-1",
};

describe("replay_conflict reader (ux U84, readers first)", () => {
  it("reads the full item: re-raised, dropping, with its ack kept and unnamed craft", () => {
    const r = decode(attentionReader, stuck());
    if (!r.ok) throw new Error(r.error.message);
    expect(r.value.source).toBe("replay_conflict");
    expect(r.value.conflict).toBe("replay_id_conflict");
    expect(r.value.state).toBe("open");
    expect(r.value.path).toBe("storage");
    expect(r.value.reraised).toBe(true);
    expect(r.value.dropping).toBe(true);
    expect(r.value.buffer).toEqual({ used_bytes: 8_600_000_000, max_bytes: 8_600_000_000 });
    expect(r.value.affected_spacecraft?.map((s) => s.name)).toEqual(["EARENDIL-001", null]);
    expect(r.value.contact?.station_code).toBe("SVA");
    expect(r.value.acknowledged_note).toBe("told domain at 03:18Z");
  });

  it("reads a pass with no scheduled contact: contact.id null, all else null (api's wire)", () => {
    const r = decode(
      attentionReader,
      stuck({ contact: { id: null, station_code: null, starts_at: null } }),
    );
    if (!r.ok) throw new Error(r.error.message);
    expect(r.value.contact).toEqual({ id: null, station_code: null, starts_at: null });
  });

  it("reads the timer path, whose stream, pass, buffer and craft are null", () => {
    const r = decode(
      attentionReader,
      stuck({
        path: "timer",
        effect_kind: "managed_action_request",
        partition_id: "endpoint:sva-1",
        partition_stopped: true,
        realized_contact_id: null,
        path_id: null,
        stream_key: null,
        contact: null,
        affected_spacecraft: [],
        spacecraft_ids: [],
        spacecraft_count: 0,
        buffer: null,
        dropping: false,
        dropping_since: null,
        acknowledged_by: null,
        acknowledged_at: null,
        acknowledged_note: null,
        reraised: false,
      }),
    );
    if (!r.ok) throw new Error(r.error.message);
    expect(r.value.partition_stopped).toBe(true);
    expect(r.value.partition_id).toBe("endpoint:sva-1");
  });

  it("keeps the whole queue readable beside a SCID-mismatch item's single spacecraft", () => {
    const item = (attention: Record<string, unknown>) => ({
      id: `attention:${String(attention["source"])}:${String(attention["id"])}`,
      priority: 1,
      kind: "attention",
      state: "critical",
      source: String(attention["source"]),
      acknowledged: null,
      since: null,
      due_at: null,
      count: 1,
      spacecraft: [],
      point: null,
      condition: null,
      plane: null,
      command: null,
      outcome: null,
      command_requests: [],
      finding: null,
      attention,
    });
    const mismatch = {
      ...settlement,
      id: "rc-9",
      source: "contact_scid_mismatch",
      conflict: null,
      backlog: undefined,
      failure_kind: undefined,
      stuck_processing_id: undefined,
      spacecraft: { id: "spacecraft-earendil-312", name: "EARENDIL-312", scid: 1 },
    };
    const r = decode(actionQueueReader, {
      observed_at: NOW.toISOString(),
      counts: { p1: 1, p2: 2, p3: 0, spacecraft_p1: 0 },
      items: [item(stuck()), item(settlement), item(mismatch)],
    });
    if (!r.ok) throw new Error(r.error.message);
    expect(r.value.items.map((i) => i.attention?.source)).toEqual([
      "replay_conflict",
      "contact_settlement",
      "contact_scid_mismatch",
    ]);
    expect(r.value.items[1]?.attention?.stuck_processing_id).toBe("rcf-1");
  });

  it("words a settlement stuck behind it without tries or a next try (U84 on U37)", () => {
    const facts = {
      lost: false,
      queued: null,
      backlog: { entries: 1204, bytes: 3_400_000 },
      failureKind: "replay_id_conflict" as const,
      failureMessage: null,
      deadline: null,
      retry: "automatic" as const,
      attempts: 3,
      nextAttemptAt: "2026-11-17T05:05:00Z",
      lastAttemptAt: null,
    };
    expect(settlementEvidence(facts, NOW)).toBe(
      "1,204 entries (3.4 MB) are on disk. Cadence can't store them until the stuck processing is fixed.",
    );
    expect(settlementEvidence({ ...facts, backlog: { entries: 1, bytes: 900 } }, NOW)).toMatch(
      /^1 entry \(.+\) is on disk\. Cadence can't store it until the stuck processing is fixed\.$/,
    );
  });

  it("closes with the system's per-path words (the action only)", () => {
    const words = (path: string | null) => {
      const r = decode(resolvedReader, {
        id: "attention:replay_conflict:rcf-1",
        source: "replay_conflict",
        conflict: "replay_id_conflict",
        path,
        spacecraft_ids: [],
        resolved_at: "2026-11-17T04:58:00Z",
        resolved_by: { kind: "system", id: null, name: null },
        action: "resumed",
      });
      if (!r.ok) throw new Error(r.error.message);
      return resolvedWords(r.value, NOW);
    };
    expect(words("storage")).toBe("Resolved: telemetry storage resumed.");
    expect(words("processing")).toBe("Resolved: processing resumed.");
    expect(words("timer")).toBe("Resolved: timed actions running.");
  });
});
