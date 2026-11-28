import { describe, expect, it } from "vite-plus/test";
import type { ResolutionAction } from "./attention.ts";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { resolvedWords } from "./attention.ts";
import { listenerTechnical } from "./listener.ts";

const NOW = new Date("2026-11-14T03:16:00Z");

/** The queue item as api serves it (domain + api shape 11-14). */
const item = (o: Record<string, unknown> = {}, priority = 1) => ({
  id: "attention:listener_refusal:rc-8",
  priority,
  kind: "attention",
  state: priority === 1 ? "critical" : "caution",
  source: "listener_refusal",
  acknowledged: null,
  since: "2026-11-14T03:10:00Z",
  due_at: "2026-11-14T03:18:00Z",
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
    id: "rc-8",
    source: "listener_refusal",
    conflict: "listener_refusal",
    state: "open",
    acknowledged_by: null,
    contact_id: "contact-8",
    reservation_id: "pass-8",
    station: { ref: "svb", id: "st-2", code: "SVB", name: "Svalbard B" },
    provider: { id: "p-1", name: "Northlight" },
    starts_at: "2026-11-14T03:10:00Z",
    ends_at: "2026-11-14T03:18:00Z",
    raised_at: "2026-11-14T03:12:00Z",
    provider_message: null,
    expires_at: "2026-11-14T03:18:00Z",
    realized_contact_id: "rc-8",
    spacecraft_id: "spacecraft-earendil-008",
    provider_profile_id: "pp-2",
    provider_profile_name: "Svalbard B shared listener",
    ground_station_ref: "svb",
    refused_count: 3,
    last_refused_at: "2026-11-14T03:14:00Z",
    last_refusal: { peer: "10.0.0.7:5021", reason: "unregistered_scid", scid: 42 },
    connected: false,
    shared_with: ["rc-9", "rc-10"],
    actions: [],
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

const CONTEXT =
  "This pass shares Northlight's listener with 2 other open passes, and Cadence refuses any connection it can't match to exactly one of them.";
const NOT_CONNECTED =
  "This pass isn't connected yet. If a refused connection was meant for it, its telemetry isn't arriving.";

describe("listener_refusal on Now (ux U50)", () => {
  it("names the pass and the count, gives the context, the reason and the pass's state", () => {
    const row = rowOf();
    expect(row?.priority).toBe(1);
    expect(row?.title).toBe("EARENDIL-008 · SVB 03:10Z pass · 3 connections refused");
    expect(row?.sentence).toBe(
      `${CONTEXT} The last one sent frames for SCID 42, which no pass on this listener expects. ${NOT_CONNECTED} Check EARENDIL-008's SCID and Northlight's profile in Setup.`,
    );
    expect(row?.meta).toBe("FIRST 03:12Z · LAST 03:14Z · STILL REFUSING");
    expect(row?.due).toEqual({ label: "LOS", at: "2026-11-14T03:18:00Z" });
    expect(row?.action).toEqual({
      label: "Open pass",
      to: { name: "ops.contacts", query: { contact: "pass-8" } },
    });
    expect(row?.command).toBeUndefined();
    expect(row?.discard).toBeUndefined();
    expect(row?.sentence).not.toContain("10.0.0.7");
  });

  it("connected: P2, no Setup line; alone on the listener; one connection", () => {
    const row = rowOf(
      {
        connected: true,
        shared_with: [],
        refused_count: 1,
        last_refused_at: "2026-11-14T03:12:00Z",
        last_refusal: { peer: null, reason: "ambiguous_scid", scid: 42 },
      },
      2,
    );
    expect(row?.title).toBe("EARENDIL-008 · SVB 03:10Z pass · 1 connection refused");
    expect(row?.sentence).toBe(
      "Cadence refuses any connection on Northlight's listener that it can't match to this pass. The last one sent frames for SCID 42, which more than one pass on this listener expects. This pass has its own connection.",
    );
    expect(row?.meta).toBe("FIRST 03:12Z · STILL REFUSING");
  });

  describe("peer_not_allowed (#993): the fix names who owns the allowed addresses", () => {
    const REFUSED =
      "The last one came from an address outside this listener's allowed source addresses, so Cadence refused it before reading anything.";
    const peer = (o: Record<string, unknown>) =>
      rowOf({
        last_refusal: { peer: "203.0.113.9:4000", reason: "peer_not_allowed", scid: null },
        ...o,
      });

    it("a provider's egress: ask the provider, Cadence can't change them", () => {
      const row = peer({ allowlist_source: "provider", transport_id: "tr-1" });
      expect(row?.sentence).toBe(
        `${CONTEXT} ${REFUSED} ${NOT_CONNECTED} Ask Northlight to check the source addresses it connects from; Cadence can't change them.`,
      );
      expect(row?.sentenceParts).toBeUndefined();
      expect(row?.sentence).not.toContain("203.0.113.9");
    });

    it("a Cadence transport: edit its allowed addresses in Setup, linked by transport_id", () => {
      const row = peer({ allowlist_source: "transport", transport_id: "tr-1" });
      expect(row?.sentence).toBe(
        `${CONTEXT} ${REFUSED} ${NOT_CONNECTED} Edit the transport's allowed source addresses in Setup.`,
      );
      const link = row?.sentenceParts?.find((p) => typeof p !== "string" && "to" in p);
      expect(link).toEqual({
        text: "allowed source addresses",
        to: { name: "setup.comms.transports", params: { transportId: "tr-1" } },
      });
      expect(row?.sentenceParts?.map((p) => (typeof p === "string" ? p : p.text)).join("")).toBe(
        row?.sentence,
      );
      expect(peer({ allowlist_source: "transport", transport_id: null })?.sentenceParts).toBe(
        undefined,
      );
    });

    it("an unknown owner (null or new): a sentence true for both", () => {
      for (const allowlist_source of [null, "relay"])
        expect(peer({ allowlist_source, transport_id: null })?.sentence).toBe(
          `${CONTEXT} ${REFUSED} ${NOT_CONNECTED} Check who sets this listener's allowed source addresses.`,
        );
    });
  });

  it("words every reason; unknown keys read as unknown", () => {
    const said = (reason: string, scid: number | null = null) =>
      rowOf({ connected: true, last_refusal: { peer: null, reason, scid } })?.sentence;
    expect(said("unregistered_scid")).toContain(
      "The last one sent frames for a spacecraft no pass on this listener expects.",
    );
    // #993: nothing emits unexpected_peer any more; an old one reads as unknown.
    expect(said("unexpected_peer")).toContain("Cadence couldn't match the last one to a pass.");
    expect(said("unidentified")).toContain(
      "Cadence couldn't tell from its first frames which spacecraft the last one was for.",
    );
    expect(said("read_failed")).toContain("Cadence couldn't read the last one's first frames.");
    expect(said("no_registered_contact")).toContain(
      "No pass was registered on this listener when the last one arrived.",
    );
    expect(said("peer_not_allowed")).toContain(
      "The last one came from an address outside this listener's allowed source addresses, so Cadence refused it before reading anything.",
    );
    expect(said("something_new")).toContain("Cadence couldn't match the last one to a pass.");
  });

  it("drops STILL REFUSING after 5 minutes, and keeps the address in Technical details", () => {
    const later = new Date("2026-11-14T03:20:00Z");
    const r = decode(actionQueueReader, {
      observed_at: later.toISOString(),
      counts: { p1: 1, p2: 0, p3: 0, spacecraft_p1: 1 },
      items: [item()],
    });
    if (!r.ok) throw new Error(r.error.message);
    expect(presentQueue(r.value, later, "EARENDIL")[0]?.meta).toBe("FIRST 03:12Z · LAST 03:14Z");
    const a = r.value.items[0]?.attention;
    if (!a) throw new Error("no attention");
    expect(listenerTechnical(a)).toEqual([
      "reason: unregistered_scid",
      "peer: 10.0.0.7:5021",
      "scid: 42",
      "listen profile: Svalbard B shared listener · pp-2",
      "ground_station_ref: svb",
      "refused: 3",
      "id: rc-8",
      "Counted live: a Cadence restart starts the count again.",
    ]);
  });

  it("own connection gone quiet: says since when, whatever connected says", () => {
    const row = rowOf({
      connected: true,
      own_quiet_since: "2026-11-14T03:14:00Z",
      last_refusal: { peer: null, reason: "second_connection", scid: 8 },
    });
    expect(row?.sentence).toBe(
      `${CONTEXT} The last one was a second connection for this pass, and Cadence keeps the first. This pass's own connection has sent nothing since 03:14Z. If the refused connection was the provider reconnecting, its telemetry isn't arriving.`,
    );
  });

  it("dates a resolution from another day (§4)", () => {
    expect(
      resolvedWords(
        {
          id: "attention:listener_refusal:rc-8",
          resolved_by: { kind: "system", id: null, name: null },
          action: "accepted",
          resolved_at: "2026-11-13T23:58:00Z",
          note: null,
        },
        NOW,
      ),
    ).toBe("Connected at 11-13 23:58Z.");
  });

  it("says how it closed", () => {
    const closed = (action: ResolutionAction, booked?: boolean) =>
      resolvedWords(
        {
          id: "attention:listener_refusal:rc-8",
          resolved_by: { kind: "system", id: null, name: null },
          action,
          resolved_at: "2026-11-14T03:19:00Z",
          note: null,
          ...(booked === undefined ? {} : { booked }),
        },
        NOW,
      );
    expect(closed("accepted")).toBe("Connected at 03:19Z.");
    expect(closed("ended", true)).toBe("The pass ended at LOS 03:19Z.");
    expect(closed("ended", false)).toBe("The contact ended at 03:19Z.");
    expect(closed("ended")).toBe("Ended at 03:19Z.");
  });
});
