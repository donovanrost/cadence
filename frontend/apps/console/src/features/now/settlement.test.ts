import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import type { MissionId } from "@/api/index.ts";
import { fetchSettlement } from "./useSettlement.ts";

// domain's #71 sample item (as in actionQueue.test.ts), with the pass's booking.
const sample = {
  id: "realized_contact_ab12",
  source: "contact_settlement",
  conflict: "unsettled",
  state: "open",
  reason: "settle_deadline",
  failure_kind: "telemetry_storage_unavailable",
  failure_message: "telemetry storage unreachable (connection refused)",
  spacecraft_id: "spacecraft-earendil-001",
  contact_id: "scheduled_contact_cd34",
  realized_contact_id: "realized_contact_ab12",
  reservation_id: "res-7",
  ground_station_ref: "svb",
  provider_id: "p-1",
  station: { ref: "svb", id: "st-1", code: "SVA", name: "Svalbard" },
  provider: { id: "p-1", name: "Northlight" },
  starts_at: "2026-11-11T18:49:00Z",
  ends_at: "2026-11-11T18:57:00Z",
  raised_at: "2026-11-12T00:57:00Z",
  deadline_at: "2026-11-12T00:57:00Z",
  backlog: { entries: 1204, bytes: 3355443, journals: 1 },
  expires_at: null,
  retry: "automatic",
  next_attempt_at: null,
  acknowledged_by: null,
  provider_message: null,
  resolution: null,
};

const reply = (data: unknown) =>
  new Response(JSON.stringify({ data }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });

afterEach(() => vi.unstubAllGlobals());

/** #847 (U37): one pass's settlement item is its own read, not the whole action queue. */
describe("fetchSettlement", () => {
  it("asks for the pass's booking and reads its open item", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>().mockResolvedValueOnce(reply(sample));
    vi.stubGlobal("fetch", fetch);
    const r = await fetchSettlement("m1" as MissionId, "res-7");
    const input = fetch.mock.calls[0]?.[0];
    const url = input instanceof Request ? input.url : (input?.toString() ?? "");
    expect(url).toContain("/missions/m1/attention/contact_settlement?reservation_id=res-7");
    expect(url).not.toContain("action-queue");
    expect(r.ok && r.value?.source).toBe("contact_settlement");
    expect(r.ok && r.value?.backlog?.entries).toBe(1204);
  });

  it("reads null when the pass has no open item", async () => {
    vi.stubGlobal("fetch", vi.fn<typeof globalThis.fetch>().mockResolvedValueOnce(reply(null)));
    const r = await fetchSettlement("m1" as MissionId, "res-8");
    expect(r).toEqual({ ok: true, value: null });
  });
});
