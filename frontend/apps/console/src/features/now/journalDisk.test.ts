import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { resolvedReader, resolvedWords } from "./attention.ts";

/** ux U66 · the telemetry buffer disk (api-ops' shape, 13d313177). */
const NOW = new Date("2026-11-15T03:20:00Z");
const holder = (o: Record<string, unknown> = {}) => ({
  realized_contact_id: "rc-8",
  contact_id: "c-8",
  spacecraft_id: "sc-8",
  spacecraft: { id: "sc-8", name: "EARENDIL-008" },
  station: { ref: "svb", id: "st-1", code: "SVB", name: "Svalbard" },
  ground_station_ref: "svb",
  starts_at: "2026-11-15T03:10:00Z",
  ends_at: "2026-11-15T03:19:00Z",
  bytes: 800_000_000,
  state: "storing",
  kept_until: null,
  ...o,
});
const disk = (o: Record<string, unknown> = {}) => ({
  percent: 72,
  used_bytes: 31_000_000_000,
  size_bytes: 43_000_000_000,
  rate_bytes_per_hour: 1_800_000_000,
  eta_full_s: 6 * 3600,
  holders: [
    holder(),
    holder({
      contact_id: "c-3",
      spacecraft: { id: "sc-3", name: "EARENDIL-003" },
      station: { ref: "ksat", id: "st-2", code: "KSAT", name: null },
      starts_at: "2026-11-15T02:40:00Z",
      bytes: 1_200_000_000,
      state: "kept",
      kept_until: "2026-11-16T02:48:00Z",
    }),
  ],
  more_count: 4,
  other_missions_bytes: 2_100_000_000,
  refusing: false,
  refused_since: null,
  ...o,
});
/** The envelope keys present as null (api-ops: the item has no pass). */
const row = (j: Record<string, unknown>, priority = 2) => {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
    items: [
      {
        id: "attention:ingress_backpressure:journal_disk",
        priority,
        kind: "attention",
        state: priority === 1 ? "critical" : "caution",
        source: "ingress_backpressure",
        acknowledged: null,
        since: "2026-11-15T03:00:00Z",
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
        attention: {
          id: "journal_disk",
          source: "ingress_backpressure",
          conflict: "journal_disk",
          state: "open",
          acknowledged_by: null,
          contact_id: null,
          station: null,
          provider: null,
          starts_at: null,
          raised_at: "2026-11-15T03:00:00Z",
          provider_message: null,
          resolution: null,
          journal_disk: j,
        },
      },
    ],
  });
  if (!r.ok) throw new Error(r.error.message);
  return presentQueue(r.value, NOW, "EARENDIL")[0];
};

describe("U66 the buffer disk", () => {
  it("70%: caution, the growth meta, holders as links, other missions unnamed", () => {
    const r = row(disk());
    expect(r?.title).toBe("Telemetry buffer disk 72% full");
    expect(r?.state).toBe("caution");
    expect(r?.meta).toBe("31 GB OF 43 GB · +1.8 GB/H · FULL IN ~6 H");
    expect(r?.sentence).toBe(
      "Cadence keeps each pass's received telemetry on this disk, until it's stored and then for 72 h for review. When the disk is full, Cadence stops accepting telemetry from every pass at once. Holding the most: EARENDIL-008 · SVB 03:10Z pass (800 MB, still being stored); EARENDIL-003 · KSAT 02:40Z pass (1.2 GB, kept until 11-16 02:48Z); and 4 more of this mission's passes; and 2.1 GB from other missions. It frees up as passes reach 72 h after they end. A pass still being stored holds its share longer. Operators can open what's holding it. The buffer's size is set where Cadence is deployed.",
    );
    const links = r?.sentenceParts?.filter((p) => typeof p !== "string");
    expect(links).toEqual([
      {
        text: "EARENDIL-008 · SVB 03:10Z pass",
        to: { name: "ops.contacts", query: { contact: "c-8" } },
      },
      {
        text: "EARENDIL-003 · KSAT 02:40Z pass",
        to: { name: "ops.contacts", query: { contact: "c-3" } },
      },
    ]);
    expect(r?.action).toEqual({
      label: "Open pass",
      to: { name: "ops.contacts", query: { contact: "c-8" } },
    });
  });

  it("90% and refusing: crit, the stop and refusal words; shrinking reads DRAINING", () => {
    expect(row(disk({ percent: 91 }), 1)?.title).toBe(
      "Telemetry buffer disk 91% full: at 100% all telemetry stops",
    );
    const full = row(
      disk({ percent: 100, refusing: true, refused_since: "2026-11-15T03:21:00Z" }),
      1,
    );
    expect(full?.title).toBe(
      "Telemetry buffer disk full: Cadence is refusing telemetry from every pass",
    );
    expect(full?.state).toBe("crit");
    expect(full?.sentence).toContain(
      "Telemetry arriving now is refused and isn't kept. It can't be recovered.",
    );
    expect(row(disk({ rate_bytes_per_hour: -900_000_000, eta_full_s: null }))?.meta).toBe(
      "31 GB OF 43 GB · −900 MB/H · DRAINING",
    );
    expect(row(disk({ rate_bytes_per_hour: null, eta_full_s: null }))?.meta).toBe("31 GB OF 43 GB");
  });

  it("no holders of this mission: no button, the other missions' share in words", () => {
    const r = row(disk({ holders: [], more_count: 0 }));
    expect(r?.noAction).toBe(true);
    expect(r?.sentence).toContain("2.1 GB of it is from other missions.");
    expect(r?.sentence).not.toContain("Operators can open");
    expect(r?.sentence).toMatch(/The buffer's size is set where Cadence is deployed\.$/);
  });

  it("closes with when it went back under, and any refusal span", () => {
    const closed = (refused: unknown) => {
      const r = decode(resolvedReader, {
        id: "attention:ingress_backpressure:journal_disk",
        resolved_by: { kind: "system", id: null, name: null },
        action: "drained",
        resolved_at: "2026-11-15T03:30:00Z",
        note: null,
        refused,
      });
      if (!r.ok) throw new Error(r.error.message);
      return resolvedWords(r.value, NOW);
    };
    expect(closed(null)).toBe("Back under 60% at 03:30Z.");
    expect(closed({ from: "2026-11-15T03:21:00Z", to: "2026-11-15T03:24:00Z" })).toBe(
      "Back under 60% at 03:30Z. Telemetry was refused from 03:21Z to 03:24Z.",
    );
  });
});
