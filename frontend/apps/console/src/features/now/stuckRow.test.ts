import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId as missionIdReader } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import StuckSheet from "./StuckSheet.vue";
import { stuckAction, stuckTechnical } from "./stuckRow.ts";

const NOW = new Date("2026-11-17T05:00:00Z");

/** A replay_conflict attention object as api sends it (11-17, U84). */
const stuck = (o: Record<string, unknown> = {}) => ({
  id: "rcf-1",
  source: "replay_conflict",
  conflict: "replay_id_conflict",
  state: "open",
  acknowledged_by: null,
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
  partition_stopped: null,
  realized_contact_id: "rc-7",
  path_id: "path-2",
  stream_key: "sva-1/downlink",
  contact: { id: "sc-7", station_code: "SVA", starts_at: "2026-11-17T02:49:00Z" },
  affected_spacecraft: [{ id: "spacecraft-earendil-001", name: "EARENDIL-001", scid: 1 }],
  spacecraft_ids: ["spacecraft-earendil-001"],
  spacecraft_count: 1,
  first_seen_at: "2026-11-17T03:10:00Z",
  last_seen_at: "2026-11-17T03:52:00Z",
  occurrences: 14,
  buffer: { used_bytes: 3_300_000_000, max_bytes: 8_600_000_000 },
  dropping: false,
  dropping_since: null,
  acknowledged_at: null,
  acknowledged_note: null,
  reraised: false,
  ...o,
});

/** A stuck settlement (U37 with failure_kind replay_id_conflict, U84 cause tag). */
const settlement = (id: string, o: Record<string, unknown> = {}) => ({
  id,
  source: "contact_settlement",
  conflict: "unsettled",
  state: "open",
  acknowledged_by: null,
  contact_id: `sc-${id}`,
  station: null,
  provider: null,
  starts_at: "2026-11-17T02:49:00Z",
  raised_at: "2026-11-17T03:30:00Z",
  provider_message: null,
  resolution: null,
  backlog: { entries: 1204, bytes: 3_400_000, journals: 1 },
  failure_kind: "replay_id_conflict",
  retry: "manual",
  stuck_processing_id: "rcf-1",
  ...o,
});

const queueItem = (attention: Record<string, unknown>, priority = 2) => ({
  id: `attention:${String(attention["source"])}:${String(attention["id"])}`,
  priority,
  kind: "attention",
  state: priority === 1 ? "critical" : "caution",
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

function rows(...attentions: Record<string, unknown>[]) {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 0, p2: attentions.length, p3: 0, spacecraft_p1: 0 },
    items: attentions.map((a) => queueItem(a)),
  });
  if (!r.ok) throw new Error(r.error.message);
  return presentQueue(r.value, NOW, "EARENDIL");
}

describe("Stuck processing on Now (ux U84 layout)", () => {
  it("is a caution row that says what's stuck, with its meta and the sheet behind it", () => {
    const [row] = rows(stuck());
    expect(row?.state).toBe("caution");
    expect(row?.title).toBe("EARENDIL-001 · SVA 02:49Z pass · telemetry storage is stuck");
    expect(row?.sentence).toBe(
      "Cadence stopped storing this pass's telemetry, so EARENDIL-001's alarms and current values aren't updating.",
    );
    expect(row?.meta).toBe("BUFFER 38% · SINCE 03:10Z · 14 TRIES");
    expect(row?.stuck?.id).toBe("rcf-1");
  });

  it("while dropping: crit, the dropping line, and Acknowledge… primary for operators", () => {
    const [row] = rows(stuck({ dropping: true, dropping_since: "2026-11-17T04:40:00Z" }));
    expect(row?.state).toBe("crit");
    expect(row?.sentence).toBe(
      "Cadence's buffer is full, so new telemetry from this pass is being lost. Telemetry received before 04:40Z is kept.",
    );
    expect(row?.meta).toBe("BUFFER FULL · LOSING NEW TELEMETRY");
    if (!row?.stuck) throw new Error("no stuck item");
    expect(stuckAction(row.stuck, true)).toEqual({ label: "Acknowledge…", primary: true });
    expect(stuckAction(row.stuck, false)).toEqual({ label: "Details", primary: false });
  });

  it("acknowledged: ACK in the meta, never in the sentence; the action is Details", () => {
    const [row] = rows(
      stuck({
        state: "acknowledged",
        acknowledged_by: { kind: "user", id: "u-1", name: "Mira K." },
        acknowledged_at: "2026-11-17T03:20:00Z",
        acknowledged_note: "told domain at 03:18Z",
      }),
    );
    expect(row?.meta).toBe("BUFFER 38% · SINCE 03:10Z · 14 TRIES · ACK MIRA K.");
    expect(row?.sentence).not.toContain("Acknowledged");
    expect(row?.acknowledged).toBe(true);
    if (!row?.stuck) throw new Error("no stuck item");
    expect(stuckAction(row.stuck, true).label).toBe("Details");
  });

  it("tags the items it causes, with no Retry storing at all (ux 11-17)", () => {
    const [one] = rows(settlement("a"));
    expect(one?.meta).toMatch(/^STUCK PROCESSING · /);
    expect(one?.command).toBeUndefined();
    expect(one?.action.label).toBe("Review");
    expect(one?.sentence).toBe(
      "1,204 entries (3.4 MB) are on disk. Cadence can't store them until the stuck processing is fixed.",
    );
    const [folded] = rows(settlement("a"), settlement("b"));
    expect(folded?.memberKeys).toHaveLength(2);
    expect(folded?.meta).toMatch(/^STUCK PROCESSING · /);
    expect(folded?.command).toBeUndefined();
    // Not caused by it: no tag, and Retry storing stays.
    const [other] = rows(
      settlement("c", { failure_kind: "settle_failed", stuck_processing_id: null }),
    );
    expect(other?.meta ?? "").not.toContain("STUCK PROCESSING");
    expect(other?.command?.label).toBe("Retry storing");
  });

  it("puts ids and internal words in Technical details only", () => {
    const r = decode(actionQueueReader, {
      observed_at: NOW.toISOString(),
      counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
      items: [queueItem(stuck({ path: "timer", partition_id: "endpoint:sva-1" }))],
    });
    if (!r.ok) throw new Error(r.error.message);
    const a = r.value.items[0]?.attention;
    if (!a) throw new Error("no attention");
    const lines = stuckTechnical(a);
    expect(lines).toContain("Source: Stuck processing (replay_conflict, replay_id_conflict)");
    expect(lines).toContain("Partition: endpoint:sva-1");
    expect(lines).toContain("Spacecraft: EARENDIL-001 (spacecraft-earendil-001)");
    expect(lines).toContain("Error: alarm_effect eff:3f2a");
    expect(lines).toContain("Occurrences: 14");
  });
});

describe("StuckSheet", () => {
  afterEach(() => vi.unstubAllGlobals());
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(status === 200 ? { data: body } : body), {
      status,
      headers: { "content-type": "application/json" },
    });
  function item(o: Record<string, unknown> = {}) {
    const r = decode(actionQueueReader, {
      observed_at: NOW.toISOString(),
      counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
      items: [queueItem(stuck(o))],
    });
    if (!r.ok) throw new Error(r.error.message);
    const a = r.value.items[0]?.attention;
    if (!a) throw new Error("no attention");
    return a;
  }
  const mountSheet = (canAck: boolean) =>
    mount(StuckSheet, {
      props: { missionId: missionIdReader("m"), canAck },
      attachTo: document.body,
    });

  it("lists the lines in ux's order and acknowledges with the note", async () => {
    const fetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>();
    fetch.mockResolvedValueOnce(reply(stuck({ state: "acknowledged" })));
    vi.stubGlobal("fetch", fetch);
    const w = mountSheet(true);
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open(); the lint type service can't resolve SFC instances.
    w.vm.open(item());
    await flushPromises();
    const text = w.text();
    const order = [
      "Stuck processing",
      "Cadence stopped storing",
      "It's a fault in Cadence",
      "Incoming telemetry is kept",
      "Tell the team that runs Cadence",
      "Copy details",
      "Technical details",
    ].map((s) => text.indexOf(s));
    expect(order.every((n, i) => n >= 0 && (i === 0 || n > (order[i - 1] ?? -1)))).toBe(true);
    await w.get("textarea").setValue("told domain at 03:18Z");
    await w
      .findAll("button")
      .find((b) => b.text() === "Acknowledge")
      ?.trigger("click");
    await flushPromises();
    const [url, init] = fetch.mock.calls[0] ?? [];
    expect(url).toContain("/attention/replay_conflict/rcf-1/acknowledge");
    expect(typeof init?.body === "string" ? JSON.parse(init.body) : null).toEqual({
      note: "told domain at 03:18Z",
    });
    expect(w.emitted("done")).toHaveLength(1);
    w.unmount();
  });

  it("says a too-long note's limit, and offers no note without operate_mission", async () => {
    const fetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>();
    fetch.mockResolvedValueOnce(
      reply({ error: { code: "invalid_note", message: "note too long" } }, 422),
    );
    vi.stubGlobal("fetch", fetch);
    const w = mountSheet(true);
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open().
    w.vm.open(item());
    await flushPromises();
    await w
      .findAll("button")
      .find((b) => b.text() === "Acknowledge")
      ?.trigger("click");
    await flushPromises();
    expect(w.text()).toContain("Keep the note to 500 characters.");
    w.unmount();
    const viewer = mountSheet(false);
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open().
    viewer.vm.open(item());
    await flushPromises();
    expect(viewer.find("textarea").exists()).toBe(false);
    expect(viewer.text()).toContain("Operators acknowledge this.");
    viewer.unmount();
  });

  it("shows who was told after the ack, for handover", async () => {
    const w = mountSheet(true);
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open().
    w.vm.open(
      item({
        state: "acknowledged",
        acknowledged_by: { kind: "user", id: "u-1", name: "Mira K." },
        acknowledged_at: "2026-11-17T03:20:00Z",
        acknowledged_note: "told domain at 03:18Z",
      }),
    );
    await flushPromises();
    expect(w.text()).toMatch(
      /Acknowledged by Mira K\. at (11-17 )?03:20Z: told domain at 03:18Z\./,
    );
    expect(w.find("textarea").exists()).toBe(false);
    w.unmount();
  });
});

describe("U84 follow-ups", () => {
  it("keeps craft names whole in the row sentence (ux: no break at the hyphen)", () => {
    const [row] = rows(
      stuck({
        path: "processing",
        affected_spacecraft: [
          { id: "spacecraft-004", name: "EARENDIL-004", scid: null },
          { id: "spacecraft-005", name: "EARENDIL-005", scid: null },
        ],
        spacecraft_count: 2,
      }),
    );
    const kept = (row?.sentenceParts ?? []).flatMap((p) =>
      typeof p !== "string" && "nowrap" in p ? [p.text] : [],
    );
    expect(kept).toEqual(["EARENDIL-004", "EARENDIL-005"]);
    const joined = (row?.sentenceParts ?? [])
      .map((p) => (typeof p === "string" ? p : p.text))
      .join("");
    expect(joined).toBe(row?.sentence);
  });

  it("tags U38's runtime item when the stuck processing caused it (ux 11-17)", () => {
    const [row] = rows({
      id: "rt-1",
      source: "mission_runtime",
      conflict: "generation_not_applied",
      state: "open",
      acknowledged_by: null,
      contact_id: null,
      station: null,
      provider: null,
      starts_at: null,
      raised_at: "2026-11-17T03:30:00Z",
      provider_message: null,
      resolution: null,
      reason: "apply_failed",
      desired_generation: 8,
      applied_generation: 7,
      stuck_processing_id: "rcf-1",
    });
    expect(row?.meta).toMatch(/^STUCK PROCESSING/);
  });
});
