import { describe, expect, it } from "vite-plus/test";
import type { ResolutionAction } from "./attention.ts";
import { decode, spacecraftId as spacecraftIdReader } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { attentionReader, resolvedWords } from "./attention.ts";
import { startReasonAction } from "./contactStart.ts";
import { NO_ACCESS_MISSED, NO_ACCESS_SEEN, noAccessText } from "./useQueueCommand.ts";

const NOW = new Date("2026-11-14T03:13:00Z");

const holder = {
  realized_contact_id: "rc-47",
  contact_id: "contact-47",
  reservation_id: "pass-47",
  spacecraft: { id: "spacecraft-earendil-047", name: "EARENDIL-047" },
  station: { ref: "sva", id: "st-1", code: "SVA", name: "Svalbard A" },
  starts_at: "2026-11-14T02:55:00Z",
  ends_at: "2026-11-14T03:11:00Z",
};

/** The queue item as api serves it (domain + api shape 11-14). */
const item = (o: Record<string, unknown> = {}, priority = 1) => ({
  id: "attention:contact_start:rc-312",
  priority,
  kind: "attention",
  state: priority === 1 ? "critical" : "caution",
  source: "contact_start",
  acknowledged: null,
  since: "2026-11-14T03:10:00Z",
  due_at: "2026-11-14T03:19:12Z",
  count: 1,
  spacecraft: [
    {
      id: "spacecraft-earendil-312",
      name: "EARENDIL-312",
      scid: 312,
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
    id: "rc-312",
    source: "contact_start",
    conflict: "not_started",
    state: "open",
    acknowledged_by: null,
    realized_contact_id: "rc-312",
    contact_id: "contact-312",
    reservation_id: "pass-312",
    station: { ref: "sva", id: "st-1", code: "SVA", name: "Svalbard A" },
    provider: { id: "p-1", name: "Northlight" },
    provider_profile_id: "pp-1",
    provider_profile_name: "Svalbard A S-band downlink",
    starts_at: "2026-11-14T03:10:00Z",
    ends_at: "2026-11-14T03:19:12Z",
    raised_at: "2026-11-14T03:10:02Z",
    provider_message: null,
    reason: "listener_in_use",
    holder,
    failure_message: "{:error, :eaddrinuse}",
    retry: "automatic",
    attempts: 3,
    last_attempt_at: "2026-11-14T03:12:40Z",
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

describe("contact_start on Now (ux U45)", () => {
  it("not started: names the pass, says why, counts down to LOS", () => {
    const row = rowOf();
    expect(row?.title).toBe("EARENDIL-312 · SVA 03:10Z pass hasn't started");
    expect(row?.sentence).toBe(
      "Cadence couldn't open the station connection because the EARENDIL-047 · SVA 02:55Z pass was still holding it.",
    );
    expect(row?.meta).toBe("CADENCE IS RETRYING · 3 TRIES");
    expect(row?.due).toEqual({ label: "LOS", at: "2026-11-14T03:19:12Z" });
    expect(row?.action).toEqual({
      label: "Open pass",
      to: { name: "ops.contacts", query: { contact: "pass-312" } },
    });
    expect(row?.command).toBeUndefined();
  });

  it("drops the try count when it isn't sent, and the holder when there's none", () => {
    const row = rowOf({ attempts: null, holder: null });
    expect(row?.meta).toBe("CADENCE IS RETRYING");
    expect(row?.sentence).toBe(
      "Cadence couldn't open the station connection because another pass was still holding it.",
    );
  });

  it("words every reason; an unknown key reads as unknown, a missing one says so", () => {
    const said = (reason: string | null) => rowOf({ reason, holder: null })?.sentence;
    expect(said("listener_unavailable")).toBe(
      "Cadence couldn't open the station connection on its side.",
    );
    expect(said("connect_failed")).toBe(
      "Cadence couldn't reach Northlight's endpoint for this pass.",
    );
    expect(said("ingress_pipeline_failed")).toBe(
      "Cadence couldn't start storing telemetry for this pass.",
    );
    expect(said("uplink_session_failed")).toBe(
      "Cadence couldn't start the uplink session for this pass.",
    );
    // U45 corrected: the row names its craft (Now has the name).
    expect(said("no_runtime_spec")).toBe(
      "No configuration has been activated on this mission yet, so passes can't start. EARENDIL-312's configuration has to be reviewed and activated first.",
    );
    expect(said("unknown")).toBe("Starting failed.");
    expect(said("something_new")).toBe("Starting failed.");
    expect(said(null)).toBe("No reason was recorded.");
  });

  it("U81 §3: names our transport and its port, never the other mission", () => {
    const claimed = (o: Record<string, unknown>) =>
      rowOf({ reason: "listen_endpoint_claimed", holder: null, ...o })?.sentence;
    const full = { listen_port: 5012, transport_id: "tr-9", transport_name: "INU S-band" };
    expect(claimed(full)).toBe(
      "Another mission already listens on the port INU S-band uses (5012). Change that transport's port.",
    );
    expect(claimed({ ...full, transport_name: null })).toBe(
      "Another mission already listens on port 5012, which this pass's transport uses. Change that transport's port.",
    );
  });

  it("U81 §3: Open transport goes to that transport's Setup page, only when it's known", () => {
    const fix = (o: Record<string, unknown>) => {
      const r = decode(
        attentionReader,
        item({ reason: "listen_endpoint_claimed", ...o }).attention,
      );
      if (!r.ok) throw new Error(r.error.message);
      return startReasonAction(r.value);
    };
    expect(fix({ listen_port: 5012, transport_id: "tr-9", transport_name: null })).toEqual({
      label: "Open transport",
      to: { name: "setup.comms.transports", params: { transportId: "tr-9" } },
    });
    expect(fix({ listen_port: 5012, transport_id: null })).toBeNull();
  });

  it("U45 transport_archived: this pass only, names the transport, Book a pass for the craft", () => {
    const said = (o: Record<string, unknown>) =>
      rowOf({ reason: "transport_archived", holder: null, ...o })?.sentence;
    const archived = {
      listen_port: null,
      provider_binding_id: null,
      transport_id: "tr-9",
      transport_name: "INU S-band",
    };
    const TAIL =
      "was archived after the pass was booked, so it can't start, and every try fails the same way. Book another pass for this spacecraft.";
    expect(said(archived)).toContain(`This pass's transport, INU S-band, ${TAIL}`);
    expect(said({ ...archived, transport_name: null })).toContain(`This pass's transport ${TAIL}`);
    const r = decode(
      attentionReader,
      item({ reason: "transport_archived", ...archived }).attention,
    );
    if (!r.ok) throw new Error(r.error.message);
    const id = decode(spacecraftIdReader, "spacecraft-earendil-312");
    if (!id.ok) throw new Error(id.error.message);
    expect(startReasonAction(r.value, id.value)).toEqual({
      label: "Book a pass",
      to: { name: "ops.contacts", query: { book: "spacecraft-earendil-312" } },
    });
    // Without the pass's craft there's nowhere to send it: no second action.
    expect(startReasonAction(r.value)).toBeNull();
  });

  it("missed: P2, the window, Mark as seen, no countdown", () => {
    const row = rowOf({ conflict: "missed", reason: null }, 2);
    expect(row?.title).toBe("EARENDIL-312 · SVA 03:10Z pass was missed");
    expect(row?.sentence).toBe(
      "The pass ended before Cadence could start it. No reason was recorded.",
    );
    expect(row?.meta).toBe("SVALBARD A S-BAND DOWNLINK · 03:10Z–03:19Z");
    expect(row?.due).toBeUndefined();
    expect(row?.command?.label).toBe("Mark as seen");
    expect(row?.command?.kind).toBe("seen");
    expect(noAccessText("seen", row?.command?.targets ?? [])).toBe(NO_ACCESS_MISSED);
    expect(noAccessText("seen", [])).toBe(NO_ACCESS_SEEN);
  });

  it("reads a pass without a booking", () => {
    const row = rowOf({ station: null, starts_at: null, ends_at: null, reservation_id: null });
    expect(row?.title).toBe("EARENDIL-312 · Pass hasn't started");
    expect(row?.due).toBeUndefined();
    expect(row?.action.to).toEqual({ name: "ops.contacts", query: { contact: "contact-312" } });
  });

  it("says how it closed", () => {
    const closed = (action: ResolutionAction, kind: "system" | "user", name: string | null) =>
      resolvedWords(
        {
          id: "attention:contact_start:rc-312",
          resolved_by: { kind, id: null, name },
          action,
          resolved_at: "2026-11-14T03:40:00Z",
          note: null,
        },
        NOW,
      );
    expect(closed("started", "system", null)).toBe("Started at 03:40Z.");
    expect(closed("acknowledged", "user", "Mira K.")).toBe("Marked as seen by Mira K. at 03:40Z.");
    // ux U45: a pass that failed to set up reads "Set up", since its start can still fail.
    expect(
      resolvedWords(
        {
          id: "attention:contact_start:sc-312",
          resolved_by: { kind: "system", id: null, name: null },
          action: "started",
          resolved_at: "2026-11-14T03:40:00Z",
          note: null,
          realized_contact_id: null,
        },
        NOW,
      ),
    ).toBe("Set up at 03:40Z.");
  });

  it("a pass that failed to set up (no realized contact): 'couldn't set up', own reasons kept", () => {
    const realization = { realized_contact_id: null, holder: null, provider_profile_id: null };
    const said = (o: Record<string, unknown>) => rowOf({ ...realization, ...o })?.sentence ?? "";
    expect(said({ reason: "unknown" })).toContain("Cadence couldn't set up this pass.");
    expect(said({ reason: "something_new" })).toContain("Cadence couldn't set up this pass.");
    expect(said({ reason: "transport_archived", transport_name: "INU S-band" })).toContain(
      "This pass's transport, INU S-band, was archived after the pass was booked",
    );
    // A realized pass keeps "Starting failed."
    expect(rowOf({ reason: "unknown", holder: null })?.sentence).toContain("Starting failed.");
    const row = rowOf({ ...realization, reason: "unknown" });
    expect(row?.action.to).toEqual({ name: "ops.contacts", query: { contact: "pass-312" } });
  });
});
