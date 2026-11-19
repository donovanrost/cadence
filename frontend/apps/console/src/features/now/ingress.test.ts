import { describe, expect, it } from "vite-plus/test";
import type { ResolutionAction } from "./attention.ts";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { resolvedWords } from "./attention.ts";
import { NO_ACCESS_ACK_LOST, noAccessText } from "./useQueueCommand.ts";

const NOW = new Date("2026-11-14T03:13:00Z");

/** The queue item as api serves it (domain + api shape 11-14). */
const item = (o: Record<string, unknown> = {}, priority = 1) => ({
  id: "attention:ingress_backpressure:journal_near_full:rc-8:pb-1",
  priority,
  kind: "attention",
  state: priority === 1 ? "critical" : "caution",
  source: "ingress_backpressure",
  acknowledged: null,
  since: "2026-11-14T03:10:00Z",
  due_at: "2026-11-14T03:19:12Z",
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
    id: "journal_near_full:rc-8:pb-1",
    source: "ingress_backpressure",
    conflict: "journal_near_full",
    state: "open",
    acknowledged_by: null,
    contact_id: "contact-8",
    reservation_id: "pass-8",
    contact_label: "SVB 03:10Z",
    station: { ref: "svb", id: "st-2", code: "SVB", name: "Svalbard B" },
    provider: { id: "p-1", name: "Northlight" },
    starts_at: "2026-11-14T03:10:00Z",
    ends_at: "2026-11-14T03:18:00Z",
    raised_at: "2026-11-14T03:12:00Z",
    provider_message: null,
    transport: { provider_binding_id: "pb-1", kind: "tcp" },
    journal_usage: {
      used_bytes: 1_740_000_000,
      capacity_bytes: 2_000_000_000,
      ratio: 0.87,
      threshold: 0.8,
      backlog_bytes: 412_000_000,
      observed_at: "2026-11-14T03:12:30Z",
      rising: true,
    },
    drops: null,
    diagnostics: { stream_id: "s-1", last_error: null },
    resolution: null,
    ...o,
  },
});

const rowOf = (o: Record<string, unknown> = {}, priority = 1) => {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 1, p2: 0, p3: 0, spacecraft_p1: 1 },
    items: [item(o, priority)],
  });
  if (!r.ok) throw new Error(r.error.message);
  return presentQueue(r.value, NOW, "EARENDIL")[0];
};

describe("ingress_backpressure on Now (ux U47)", () => {
  it("journal near full: backing up, buffer %, rising, waiting bytes, no command", () => {
    const row = rowOf();
    expect(row?.title).toBe("EARENDIL-008 · SVB 03:10Z pass · telemetry is backing up");
    expect(row?.sentence).toBe(
      "Cadence is storing this pass's telemetry more slowly than it arrives. At 100% Cadence stops reading, and new telemetry arrives late.",
    );
    expect(row?.meta).toBe("BUFFER 87% · RISING · 412 MB WAITING");
    expect(row?.action).toEqual({
      label: "Open pass",
      to: { name: "ops.contacts", query: { contact: "pass-8" } },
    });
    expect(row?.command).toBeUndefined();
    const full = rowOf({
      journal_usage: {
        used_bytes: 1_920_000_000,
        capacity_bytes: 2_000_000_000,
        ratio: 0.96,
        threshold: 0.8,
        backlog_bytes: 0,
        observed_at: "2026-11-14T03:13:00Z",
        rising: false,
      },
    });
    expect(full?.sentence).toBe(
      "The buffer is almost full. Cadence is storing this pass's telemetry more slowly than it arrives. At 100% Cadence stops reading, and new telemetry arrives late.",
    );
    expect(full?.meta).toBe("BUFFER 96%");
  });

  it("frames dropped: count, bytes, span, Acknowledge; a contact without a pass", () => {
    const o = {
      id: "frames_dropped:rc-8:pb-1",
      conflict: "frames_dropped",
      journal_usage: null,
      drops: {
        count: 12,
        bytes: 48_000,
        first_at: "2026-11-14T03:14:00Z",
        last_at: "2026-11-14T03:15:00Z",
        buffer: "executor",
      },
    };
    const row = rowOf(o);
    expect(row?.title).toBe("EARENDIL-008 · SVB 03:10Z pass · 12 telemetry frames lost");
    expect(row?.sentence).toBe(
      "Cadence's buffer was full, so these frames from Northlight were dropped. Cadence can't recover them.",
    );
    expect(row?.meta).toBe("12 FRAMES · 48 KB · 03:14Z–03:15Z");
    expect(row?.command?.label).toBe("Acknowledge");
    expect(noAccessText("seen", row?.command?.targets ?? [])).toBe(NO_ACCESS_ACK_LOST);
    const bare = rowOf({ ...o, reservation_id: null, contact_label: null });
    expect(bare?.title).toBe("EARENDIL-008 · SVB contact · 12 telemetry frames lost");
    const acked = rowOf({
      ...o,
      state: "acknowledged",
      acknowledged_by: { kind: "user", id: "u-1", name: "Mira K." },
    });
    expect(acked?.command).toBeUndefined();
    expect(acked?.meta).toBe("12 FRAMES · 48 KB · 03:14Z–03:15Z · ACK MIRA K.");
  });

  it("says how it closed", () => {
    const closed = (action: ResolutionAction, kind: "system" | "user", name: string | null) =>
      resolvedWords(
        {
          id: "attention:ingress_backpressure:frames_dropped:rc-8:pb-1",
          resolved_by: { kind, id: null, name },
          action,
          resolved_at: "2026-11-14T03:22:00Z",
          note: null,
        },
        NOW,
      );
    expect(closed("drained", "system", null)).toBe("Caught up at 03:22Z.");
    expect(closed("acknowledged", "user", "Mira K.")).toBe("Acknowledged by Mira K. at 03:22Z.");
  });
});
