import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { attentionReader, type Attention } from "./attention.ts";
import {
  affects,
  bufferLine,
  stuckAckLine,
  stuckMeta,
  stuckTitle,
  stuckWhy,
  whatStopped,
} from "./stuckProcessing.ts";

const NOW = new Date("2026-11-17T05:00:00Z");
const sc = (n: string | null, id = n ?? "x") => ({ id: `spacecraft-${id}`, name: n, scid: null });

/** A storage item filling its buffer, read through the attention reader (U84). */
function stuck(o: Record<string, unknown> = {}): Attention {
  const r = decode(attentionReader, {
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
    contact: { id: "sc-7", station_code: "SVA", starts_at: "2026-11-17T02:49:00Z" },
    affected_spacecraft: [sc("EARENDIL-001")],
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
    partition_stopped: null,
    ...o,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
}

describe("Stuck processing words (ux U84)", () => {
  it("titles storage with its lead craft and the pass", () => {
    expect(stuckTitle(stuck(), NOW)).toBe(
      "EARENDIL-001 · SVA 02:49Z pass · telemetry storage is stuck",
    );
    const three = stuck({ affected_spacecraft: [sc("EARENDIL-001"), sc("A"), sc("B")] });
    expect(stuckTitle(three, NOW)).toBe(
      "EARENDIL-001 and 2 others · SVA 02:49Z pass · telemetry storage is stuck",
    );
    // U25: an unnamed only craft is never shown by id; the pass leads.
    expect(stuckTitle(stuck({ affected_spacecraft: [sc(null)] }), NOW)).toBe(
      "SVA 02:49Z pass · telemetry storage is stuck",
    );
  });

  it("names nobody in the processing and timer titles", () => {
    expect(stuckTitle(stuck({ path: "processing" }), NOW)).toBe("Incoming data is stuck");
    expect(stuckTitle(stuck({ path: "timer" }), NOW)).toBe("Timed actions are stuck");
  });

  it("never claims an exact set off storage, and counts unnamed craft (ux 11-17)", () => {
    const words = (list: unknown[], count = list.length) =>
      affects(stuck({ path: "processing", affected_spacecraft: list, spacecraft_count: count }));
    expect(words([sc("EARENDIL-009")])).toBe("It affects EARENDIL-009, and may affect others.");
    expect(words([sc("EARENDIL-004"), sc("EARENDIL-005")])).toBe(
      "It affects at least 2 spacecraft: EARENDIL-004 and EARENDIL-005.",
    );
    expect(words([sc("EARENDIL-004"), sc("EARENDIL-005"), sc(null)])).toBe(
      "It affects at least 3 spacecraft, including EARENDIL-004 and EARENDIL-005.",
    );
    expect(words([sc("A"), sc("B"), sc("C"), sc("D")])).toBe(
      "It affects at least 4 spacecraft, including A, B and C.",
    );
    expect(words([sc(null)])).toBe("It affects at least 1 spacecraft.");
    expect(words([], 0)).toBe("It isn't known yet which spacecraft it affects.");
    // A count above the list (api may know more ids than names) still says "at least".
    expect(words([sc("EARENDIL-004")], 3)).toBe(
      "It affects at least 3 spacecraft, including EARENDIL-004.",
    );
    expect(
      whatStopped(stuck({ path: "timer", affected_spacecraft: [], spacecraft_count: 0 })),
    ).toBe("Timed actions aren't running. It isn't known yet which spacecraft it affects.");
  });

  it("storage with several craft speaks of the pass's spacecraft", () => {
    expect(whatStopped(stuck({ affected_spacecraft: [sc("A"), sc("B")] }))).toBe(
      "Cadence stopped storing this pass's telemetry, so alarms and current values for this pass's spacecraft aren't updating.",
    );
  });

  it("says what stopped, why (tries since, the last at), and drops null clauses", () => {
    expect(whatStopped(stuck())).toBe(
      "Cadence stopped storing this pass's telemetry, so EARENDIL-001's alarms and current values aren't updating.",
    );
    expect(stuckWhy(stuck(), NOW)).toBe(
      "It's a fault in Cadence, not in this mission's setup or data. Cadence retries by itself and hits the same fault each time: 14 tries since 03:10Z, the last at 03:52Z.",
    );
    expect(stuckWhy(stuck({ occurrences: null, last_seen_at: null }), NOW)).toMatch(
      /each time: since 03:10Z\.$/,
    );
    expect(
      stuckWhy(stuck({ occurrences: null, first_seen_at: null, last_seen_at: null }), NOW),
    ).toMatch(/hits the same fault each time\.$/);
  });

  it("stopped at start has no counts: STOPPED · SINCE (U84 (3))", () => {
    const stopped = stuck({ path: "timer", partition_stopped: true, buffer: null });
    expect(stuckWhy(stopped, NOW)).toBe(
      "It's a fault in Cadence, not in this mission's setup or data. It stopped while starting up and won't start again until Cadence is fixed.",
    );
    expect(stuckMeta(stopped, NOW)).toBe("STOPPED · SINCE 03:10Z");
  });

  it("words the buffer filling and full, with its meta", () => {
    expect(bufferLine(stuck(), NOW)).toBe(
      "Incoming telemetry is kept in Cadence's buffer meanwhile: 3.3 of 8.6 GB used. Once it's full, new telemetry is lost.",
    );
    expect(stuckMeta(stuck(), NOW)).toBe("BUFFER 38% · SINCE 03:10Z · 14 TRIES");
    const full = stuck({ dropping: true, dropping_since: "2026-11-17T04:40:00Z" });
    expect(bufferLine(full, NOW)).toBe(
      "Cadence's buffer is full, so new telemetry from this pass is being lost. Telemetry received before 04:40Z is kept.",
    );
    expect(bufferLine(stuck({ path: "processing", dropping: true }), NOW)).toMatch(
      /^Cadence's buffer is full, so new telemetry from these spacecraft is being lost\./,
    );
    expect(bufferLine(stuck({ dropping: true }), NOW)).toMatch(
      /Telemetry already received is kept\.$/,
    );
    expect(stuckMeta(full, NOW)).toBe("BUFFER FULL · LOSING NEW TELEMETRY");
    expect(bufferLine(stuck({ path: "timer", buffer: null }), NOW)).toBeNull();
  });

  it("says who acknowledged, with the note, and before the loss when re-raised", () => {
    const acked = {
      state: "acknowledged",
      acknowledged_by: { kind: "user", id: "u-1", name: "Mira K." },
      acknowledged_at: "2026-11-17T03:20:00Z",
      acknowledged_note: "told domain at 03:18Z",
    };
    expect(stuckAckLine(stuck(acked), NOW)).toBe(
      "Acknowledged by Mira K. at 03:20Z: told domain at 03:18Z.",
    );
    expect(stuckAckLine(stuck({ ...acked, acknowledged_note: null }), NOW)).toBe(
      "Acknowledged by Mira K. at 03:20Z.",
    );
    expect(stuckMeta(stuck(acked), NOW)).toBe("BUFFER 38% · SINCE 03:10Z · 14 TRIES · ACK MIRA K.");
    const reraised = stuck({ ...acked, state: "open", reraised: true, dropping: true });
    expect(stuckAckLine(reraised, NOW)).toBe(
      "Acknowledged by Mira K. at 03:20Z, before new telemetry started being lost: told domain at 03:18Z.",
    );
    expect(stuckMeta(reraised, NOW)).not.toContain("ACK");
    expect(stuckAckLine(stuck(), NOW)).toBeNull();
  });

  it("keeps ids and internal words out of every visible line", () => {
    for (const path of ["storage", "processing", "timer"]) {
      const a = stuck({ path, affected_spacecraft: [sc(null, "hidden")], spacecraft_count: 1 });
      const text = [stuckTitle(a, NOW), whatStopped(a), stuckWhy(a, NOW), bufferLine(a, NOW)]
        .join(" ")
        .toLowerCase();
      expect(text).not.toMatch(
        /spacecraft-hidden|replay|conflict|partition|journal|effect|runtime/,
      );
    }
  });
});
