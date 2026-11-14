import type { ReadyPlacement, WorkspaceFrame } from "./snapshot.ts";
import { frameRows, type Row } from "./widget-data.ts";

/**
 * A time-series placement's overlay frames as the chart's marker inputs (Fix 10 (c)). The
 * snapshot already carries them (WidgetRegistry: optional `limits` and `events` overlays);
 * neither viewer drew them before. The chart admits plain records (chart-input readMarkers).
 *
 * - limits, definition intervals (active_from/to + red/yellow low/high) → `limit_definition_interval`
 * - limits, events (time + normalized_state/limit_state)                  → `limit_event`, only on
 *   entry into a red or yellow state (ux: marks on entry, not on every violating sample)
 * - events, intervals (starts_at/ends_at: contacts)                        → `contact_interval`
 * - events, the mission timeline (mission_event_id)                       → `mission_event`
 *   The events source also sends source-health, watermark, capability, backfill and revision
 *   frames (same occurred_at columns); they're evidence, not chart marks (a watermark advances
 *   about once a second during a pass: qa's overlay look), so only the mission timeline is read.
 *
 * `link_id` is the marker's own id: the renderers need one, and the console's chart port treats
 * evidence links as no-ops.
 */
export type MarkerInput = Readonly<Record<string, string | number | null>>;
export type OverlayMarkers = Readonly<{
  limitMarkers: readonly MarkerInput[];
  eventMarkers: readonly MarkerInput[];
}>;

const num = (v: Row[string] | undefined) => (typeof v === "number" ? v : null);
const text = (v: Row[string] | undefined) => (typeof v === "string" && v ? v : null);
const has = (frame: WorkspaceFrame, ...names: string[]) =>
  names.every((n) => frame.fields.some((f) => f.name === n));

function limitInterval(row: Row, key: string): MarkerInput | null {
  const from = num(row.active_from);
  if (from === null) return null;
  const id = `limit-definition-${key}`;
  return {
    marker_type: "limit_definition_interval",
    marker_id: id,
    link_id: id,
    starts_at_ms: from,
    ends_at_ms: num(row.active_to),
    limit_definition_id: text(row.limit_definition_id),
    limit_definition_version: num(row.limit_definition_version),
    limit_set_name: text(row.limit_set_name),
    red_low: num(row.red_low),
    yellow_low: num(row.yellow_low),
    yellow_high: num(row.yellow_high),
    red_high: num(row.red_high),
  };
}

function limitEvent(row: Row, key: string): MarkerInput | null {
  const at = num(row.time);
  if (at === null) return null;
  const id = text(row.limit_event_id) ?? text(row.sample_id) ?? `limit-event-${key}`;
  return {
    marker_type: "limit_event",
    marker_id: id,
    link_id: id,
    timestamp_ms: at,
    normalized_state: text(row.normalized_state),
    limit_event_id: text(row.limit_event_id),
    sample_id: text(row.sample_id),
    limit_definition_id: text(row.limit_definition_id),
  };
}

function contactInterval(row: Row, key: string): MarkerInput | null {
  const from = num(row.starts_at);
  if (from === null) return null;
  const id = text(row.contact_id) ?? `contact-${key}`;
  return {
    marker_type: "contact_interval",
    marker_id: id,
    link_id: id,
    starts_at_ms: from,
    ends_at_ms: num(row.ends_at),
    label: text(row.label),
    title: text(row.label),
    status: text(row.status),
    /** scheduled_contact (booked: dashed) vs realized_contact (flown: filled), ux. */
    kind: text(row.kind),
    /** Ground-station code (api 3d4c70d21; null when the contact has no transport); the band falls back to label. */
    station: text(row.station),
  };
}

function pointEvent(row: Row, key: string): MarkerInput | null {
  const at = num(row.occurred_at) ?? num(row.time);
  if (at === null) return null;
  const id = text(row.mission_event_id) ?? text(row.event_id) ?? `event-${key}`;
  return {
    marker_type: "mission_event",
    marker_id: id,
    link_id: id,
    timestamp_ms: at,
    title: text(row.title) ?? text(row.label) ?? text(row.kind),
    severity: text(row.severity),
  };
}

/** red/yellow (or critical/caution) entries only: a mark where the state changes into a violation. */
const violation = (row: Row): string | null => {
  const state = text(row.limit_state) ?? text(row.normalized_state);
  if (state === "red" || state === "critical") return "red";
  if (state === "yellow" || state === "caution") return "yellow";
  return null;
};
function limitEntries(frame: WorkspaceFrame, f: number): MarkerInput[] {
  const rows = frameRows(frame)
    .map((row, r) => ({ row, r }))
    .filter(({ row }) => num(row.time) !== null)
    .sort((a, b) => (num(a.row.time) ?? 0) - (num(b.row.time) ?? 0));
  let previous: string | null = null;
  return rows.flatMap(({ row, r }) => {
    const state = violation(row);
    const entry = state !== null && state !== previous;
    previous = state;
    const marker = entry ? limitEvent(row, `${f}-${r}`) : null;
    return marker ? [{ ...marker, limit_state: state }] : [];
  });
}

function collect(
  frames: readonly WorkspaceFrame[],
  pick: (frame: WorkspaceFrame) => ((row: Row, key: string) => MarkerInput | null) | null,
): MarkerInput[] {
  return frames.flatMap((frame, f) => {
    const read = pick(frame);
    return read
      ? frameRows(frame).flatMap((row, r) => {
          const marker = read(row, `${f}-${r}`);
          return marker ? [marker] : [];
        })
      : [];
  });
}

export function overlayMarkers(placement: ReadyPlacement): OverlayMarkers {
  const limits = placement.frames.filter((f) => f.role === "limits");
  const events = placement.frames.filter((f) => f.role === "events");
  return {
    limitMarkers: [
      ...collect(limits, (f) => (has(f, "active_from") ? limitInterval : null)),
      ...limits.flatMap((f, i) =>
        !has(f, "active_from") && has(f, "time") ? limitEntries(f, i) : [],
      ),
    ],
    eventMarkers: collect(events, (f) =>
      has(f, "starts_at") ? contactInterval : has(f, "mission_event_id") ? pointEvent : null,
    ),
  };
}
