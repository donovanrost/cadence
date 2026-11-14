import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { field, frame, snapshotJson } from "../fixtures.test-support.ts";
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
    expect(overlayMarkers(p).limitMarkers.map((m) => [m.marker_id, m.limit_state])).toEqual([
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
    expect(overlayMarkers(p).eventMarkers.map((m) => [m.marker_id, m.station, m.label])).toEqual([
      ["c-1", "SVL", "NL-ABC123"],
      ["c-2", null, "NL-DEF456"],
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
    expect(overlayMarkers(p).eventMarkers.map((m) => [m.marker_id, m.title])).toEqual([
      ["mission_event_id-1", "Pass started"],
      ["mission_event_id-2", "Pass started"],
    ]);
  });
});
