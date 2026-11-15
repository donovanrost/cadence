import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { field, frame, snapshotJson } from "../fixtures.test-support.ts";
import { contactTitle } from "../chart/chart-events.ts";
import { overlayMarkers } from "./overlay-markers.ts";
import { workspaceSnapshot, type ReadyPlacement } from "./snapshot.ts";

function placementWith(frames: ReturnType<typeof frame>[]): ReadyPlacement {
  const json = snapshotJson("time_series");
  const p = json.placements[0];
  if (p) p.frames = [...p.frames, ...frames];
  const r = decode(workspaceSnapshot, json);
  const placement = r.ok ? r.value.placements[0] : undefined;
  if (placement?.status !== "ready") throw new Error("fixture");
  return placement;
}

describe("overlay frames as chart markers", () => {
  it("turns limit definition intervals into threshold markers", () => {
    const p = placementWith([
      frame(
        "intervals",
        [
          field("active_from", "time", [1_000]),
          field("active_to", "time", [5_000]),
          field("limit_definition_id", "string", ["def-1"]),
          field("red_low", "number", [10]),
          field("yellow_low", "number", [20]),
          field("yellow_high", "number", [30]),
          field("red_high", "number", [40]),
        ],
        "limits",
      ),
    ]);
    expect(overlayMarkers(p).limitMarkers).toEqual([
      expect.objectContaining({
        marker_type: "limit_definition_interval",
        starts_at_ms: 1_000,
        ends_at_ms: 5_000,
        red_high: 40,
        yellow_low: 20,
      }),
    ]);
  });

  it("marks limit events only on entry into a red or yellow state", () => {
    const p = placementWith([
      frame(
        "events",
        [
          field("time", "time", [1_000, 2_000, 3_000, 4_000, 5_000]),
          field("limit_state", "enum", ["yellow", "yellow", "red", "green", "red"]),
          field("limit_event_id", "string", ["a", "b", "c", "d", "e"]),
        ],
        "limits",
      ),
    ]);
    const entries = overlayMarkers(p).limitMarkers.flatMap((m) =>
      m.marker_type === "limit_event" ? [[m.marker_id, m.limit_state]] : [],
    );
    expect(entries).toEqual([
      ["a", "yellow"],
      ["c", "red"],
      ["e", "red"],
    ]);
  });

  it("turns contact intervals into bands that keep booked vs realized", () => {
    const p = placementWith([
      frame(
        "intervals",
        [
          field("starts_at", "time", [1_000]),
          field("ends_at", "time", [2_000]),
          field("kind", "enum", ["scheduled_contact"]),
          field("status", "enum", ["scheduled"]),
          field("label", "string", ["NL-ABC123"]),
          field("contact_id", "string", ["sc-1"]),
        ],
        "events",
      ),
    ]);
    expect(overlayMarkers(p).eventMarkers).toEqual([
      expect.objectContaining({
        marker_type: "contact_interval",
        marker_id: "sc-1",
        kind: "scheduled_contact",
        label: "NL-ABC123",
        station: null,
      }),
    ]);
  });

  it("carries the contact's ground-station code for the band (api 3d4c70d21)", () => {
    const p = placementWith([
      frame(
        "intervals",
        [
          field("starts_at", "time", [1_000, 3_000]),
          field("ends_at", "time", [2_000, 4_000]),
          field("kind", "enum", ["realized_contact", "scheduled_contact"]),
          field("label", "string", ["NL-ABC123", "NL-DEF456"]),
          field("contact_id", "string", ["c-1", "c-2"]),
          field("station", "string", ["SVL", null]),
        ],
        "events",
      ),
    ]);
    const bands = overlayMarkers(p).eventMarkers.flatMap((m) =>
      m.marker_type === "contact_interval" ? [[m.marker_id, m.station, m.label, m.kind]] : [],
    );
    expect(bands).toEqual([
      ["c-1", "SVL", "NL-ABC123", "realized_contact"],
      ["c-2", null, "NL-DEF456", "scheduled_contact"],
    ]);
  });
  it("marks mission timeline events only, not the watermark or other evidence frames", () => {
    const events = (idField: string, title: string) =>
      frame(
        "events",
        [
          field("occurred_at", "time", [1_000, 2_000]),
          field("title", "string", [title, title]),
          field(idField, "string", [`${idField}-1`, `${idField}-2`]),
        ],
        "events",
      );
    const p = placementWith([
      events("mission_event_id", "Pass started"),
      events("source_watermark_event_id", "Telemetry watermark advanced"),
    ]);
    const marks = overlayMarkers(p).eventMarkers.flatMap((m) =>
      m.marker_type === "mission_event" ? [[m.marker_id, m.title]] : [],
    );
    expect(marks).toEqual([
      ["mission_event_id-1", "Pass started"],
      ["mission_event_id-2", "Pass started"],
    ]);
  });
  it("reads a contact kind it doesn't know as neither booked nor flown", () => {
    const p = placementWith([
      frame(
        "intervals",
        [
          field("starts_at", "time", [1_000]),
          field("ends_at", "time", [2_000]),
          field("kind", "enum", ["maintenance_window"]),
          field("contact_id", "string", ["c-1"]),
        ],
        "events",
      ),
    ]);
    expect(overlayMarkers(p).eventMarkers).toEqual([
      expect.objectContaining({ marker_type: "contact_interval", kind: null }),
    ]);
  });
  it("reads a contact that closed without starting, and why (domain's frame)", () => {
    const p = placementWith([
      frame(
        "intervals",
        [
          field("starts_at", "time", [1_000, 3_000, 5_000]),
          field("ends_at", "time", [2_000, 4_000, 6_000]),
          field("kind", "enum", ["realized_contact", "realized_contact", "scheduled_contact"]),
          field("contact_id", "string", ["c-1", "c-2", "c-3"]),
          field("started", "boolean", [false, true, null]),
          field("close_reason", "string", ["window_ended", null, null]),
        ],
        "events",
      ),
    ]);
    expect(
      overlayMarkers(p).eventMarkers.map((m) =>
        m.marker_type === "contact_interval" ? [m.marker_id, m.started, m.close_reason] : null,
      ),
    ).toEqual([
      ["c-1", false, "window_ended"],
      ["c-2", true, null],
      ["c-3", null, null],
    ]);
  });
  it("reads 003's ZKgUX as dev stores it: a booking that never started (domain 1b43c321c)", () => {
    const at = (iso: string) => Date.parse(iso);
    const p = placementWith([
      frame(
        "intervals",
        [
          field("starts_at", "time", [at("2026-11-10T03:05:57Z")]),
          field("ends_at", "time", [at("2026-11-10T03:13:57Z")]),
          field("kind", "enum", ["realized_contact"]),
          field("status", "enum", ["stopped"]),
          field("contact_id", "string", ["scheduled_contact_ZKgUX7v3IM50LiWbGHnL83Ug_run"]),
          field("station", "string", ["FAI"]),
          field("started", "boolean", [false]),
          field("close_reason", "string", ["window_ended"]),
          field("scheduled_starts_at", "time", [at("2026-11-10T03:05:57Z")]),
          field("scheduled_ends_at", "time", [at("2026-11-10T03:13:57Z")]),
        ],
        "events",
      ),
    ]);
    const [band] = overlayMarkers(p).eventMarkers;
    if (band?.marker_type !== "contact_interval") throw new Error("expected a contact band");
    expect([band.started, band.close_reason, (band.ends_at_ms ?? 0) - band.starts_at_ms]).toEqual([
      false,
      "window_ended",
      8 * 60_000,
    ]);
    expect(contactTitle(band, false)).toBe("FAI pass · didn't start: its window ended first");
  });
});
