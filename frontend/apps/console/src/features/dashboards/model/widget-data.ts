import { formatAbsolute, type OpState } from "@/ui";
import type { WorkspaceField, WorkspaceFrame, WorkspacePlacement } from "./snapshot.ts";

/**
 * Pure widget projections over a resolved placement. Ported from the dashboards module
 * (`features/dashboard/widget-data.ts` @ a0a5ac83); limit tones now map to the Apogee state grammar.
 */

export type Cell = WorkspaceField["values"][number];
export type Row = Record<string, Cell>;

/** Ground-system limit states, worst first. Panel config never chooses a state. */
export const limitStates = ["red", "yellow", "blue", "green"] as const;
export type LimitState = (typeof limitStates)[number];
/** Ground limit state → Apogee mark (shape + color + word). Advisory has no hue of its own. */
export const limitMark: Readonly<Record<LimitState | "no_data", OpState>> = {
  red: "crit",
  yellow: "caution",
  blue: "neutral",
  green: "nominal",
  no_data: "stale",
};
export const limitLabel: Readonly<Record<LimitState | "no_data", string>> = {
  red: "Red limit",
  yellow: "Yellow limit",
  blue: "Advisory",
  green: "Nominal",
  no_data: "No data",
};

export function frameRows(frame: WorkspaceFrame): Row[] {
  const length = frame.fields[0]?.values.length ?? 0;
  return Array.from({ length }, (_, index) =>
    Object.fromEntries(frame.fields.map((field) => [field.name, field.values[index] ?? null])),
  );
}

/**
 * A widget's name for its heading and labels (B7): its title, else "Untitled widget N", N its
 * place in reading order within its section (ux #461), so two untitled widgets don't share a name.
 */
export const widgetTitle = (placement: WorkspacePlacement, position?: number): string =>
  placement.status === "ready"
    ? placement.widget.title || untitled("widget", position)
    : "Unavailable widget";

/**
 * Reading order on the grid: by row, then column; a placement without a position comes last. The
 * viewer and edit mode both sort by it, so "Untitled widget N" is the same widget in both.
 */
export const readingOrder = (p: { layout: { x: number | null; y: number | null } }): number =>
  (p.layout.y ?? 1e6) * 1000 + (p.layout.x ?? 0);

/** "Untitled widget 3", "Untitled section 2"; without a position, just the kind. */
export const untitled = (kind: "widget" | "section", position?: number): string =>
  position === undefined ? `Untitled ${kind}` : `Untitled ${kind} ${position}`;

type LaneSegment = Readonly<{ state: string; limit: LimitState | null; from: number }>;
const limitWords = (s: LaneSegment) => (s.limit ? limitLabel[s.limit].toLowerCase() : null);

/**
 * A lane of the state timeline as a sentence (B5): its states, from when, and the last one in the
 * window. "Last", not "now": the window may end before the present (U20, ux #461).
 */
export function laneSentence(label: string, segments: readonly LaneSegment[]): string {
  const words = (s: LaneSegment) => `${s.state}${s.limit ? ` (${limitWords(s)})` : ""}`;
  const first = segments[0];
  const last = segments.at(-1);
  if (!first || !last) return `${label}: no states.`;
  const n = segments.length;
  return n === 1
    ? `${label}: ${words(last)} from ${formatTime(first.from)}.`
    : `${label}: ${n} states from ${formatTime(first.from)}, last ${words(last)}.`;
}

/**
 * One segment as text for the lane's screen-reader list (B5): the lane image's segments are
 * presentational, so each state and when it started is said here, not only in the hover title.
 */
export const segmentLine = (s: LaneSegment): string =>
  `${s.state}${s.limit ? `, ${limitWords(s)},` : ""} from ${formatTime(s.from)}`;

export const primaryFrames = (placement: WorkspacePlacement) =>
  placement.frames.filter((frame) => frame.role === "primary");

export function hasData(placement: WorkspacePlacement): boolean {
  return primaryFrames(placement).some((f) => f.fields.some((field) => field.values.length > 0));
}

export function formatValue(value: Cell | undefined, field: WorkspaceField, precision: number) {
  if (value === null || value === undefined) return "—";
  if (field.kind === "time" && typeof value === "number") return formatTime(value);
  if (typeof value === "number") return value.toFixed(precision);
  return String(value);
}

export function formatTime(ms: number): string {
  const date = new Date(ms);
  return Number.isNaN(date.getTime()) ? "—" : formatAbsolute(date);
}

function asLimitState(value: Cell | undefined): LimitState | null {
  return limitStates.find((state) => state === value) ?? null;
}

/** The worst current limit state across limit overlays and limit-state columns. */
export function worstLimitState(placement: WorkspacePlacement): LimitState | null {
  const states = placement.frames.flatMap((frame) =>
    frame.fields
      .filter(
        (field) =>
          ["limit_state", "worst_state"].includes(field.name) ||
          (frame.role === "limits" && field.name === "normalized_state"),
      )
      .map((field) => asLimitState(field.values.at(-1))),
  );
  return limitStates.find((state) => states.includes(state)) ?? null;
}

/** Newest sample time in the primary frames, for staleness display. */
export function latestSampleMs(placement: WorkspacePlacement): number | null {
  let latest: number | null = null;
  for (const frame of primaryFrames(placement))
    for (const field of frame.fields)
      if (field.kind === "time")
        for (const value of field.values)
          if (typeof value === "number" && (latest === null || value > latest)) latest = value;
  return latest;
}

export type ValueTileData =
  | { kind: "value"; text: string; unit: string | null; at: number | null; numeric: number | null }
  | { kind: "empty" }
  | { kind: "ambiguous" };

export function valueTile(placement: WorkspacePlacement): ValueTileData {
  const frames = primaryFrames(placement);
  const frame = frames[0];
  if (frames.length !== 1 || !frame)
    return frames.length ? { kind: "ambiguous" } : { kind: "empty" };
  const values =
    frame.shape === "matrix"
      ? frame.fields.filter((f) => f.name === "value")
      : frame.fields.filter((f) => f.kind !== "time");
  const field = values[0];
  if (values.length !== 1 || !field) return { kind: "ambiguous" };
  const last = field.values.length - 1;
  if (last < 0) return { kind: "empty" };
  const value = field.values[last] ?? null;
  const time = frame.fields.find((f) => f.kind === "time")?.values[last];
  const unitField = frame.fields.find((f) => f.name === "unit")?.values[last];
  return {
    kind: "value",
    text: formatValue(value, field, placement.widget?.options.precision ?? 2),
    unit: field.unit ?? (typeof unitField === "string" ? unitField : null),
    at: typeof time === "number" ? time : null,
    numeric: typeof value === "number" ? value : null,
  };
}

export type TableData = {
  columns: Array<{ key: string; label: string; field: WorkspaceField }>;
  rows: Array<{
    key: string;
    cells: Array<{ key: string; text: string; state: LimitState | null }>;
  }>;
};

/** Field identity includes kind and unit, so unlike columns are never merged. */
export function table(placement: WorkspacePlacement): TableData {
  const precision = placement.widget?.options.precision ?? 2;
  const frames = primaryFrames(placement);
  const columns = Array.from(
    new Map(
      frames.flatMap((frame) =>
        frame.fields.map(
          (field) => [JSON.stringify([field.name, field.kind, field.unit]), field] as const,
        ),
      ),
    ),
    ([key, field]) => ({
      key,
      field,
      label: `${field.name.replaceAll("_", " ")}${field.unit ? ` (${field.unit})` : ""}`,
    }),
  );
  const rows = frames.flatMap((frame, frameIndex) =>
    frameRows(frame).map((row, rowIndex) => ({
      key: `${frameIndex}:${rowIndex}`,
      cells: columns.map(({ key, field }) => {
        const present = frame.fields.some(
          (f) => f.name === field.name && f.kind === field.kind && f.unit === field.unit,
        );
        const value = present ? row[field.name] : undefined;
        return {
          key,
          text: present ? formatValue(value, field, precision) : "—",
          state: asLimitState(value),
        };
      }),
    })),
  );
  return { columns, rows };
}

export type TimelineEvent = {
  key: string;
  at: number;
  ends: number | null;
  title: string;
  category: string | null;
  severity: string | null;
};

export function events(placement: WorkspacePlacement): TimelineEvent[] {
  return primaryFrames(placement)
    .filter((frame) => frame.shape === "events" || frame.shape === "intervals")
    .flatMap((frame, frameIndex) =>
      frameRows(frame).flatMap((row, index) => {
        const at = row.occurred_at ?? row.time ?? row.starts_at;
        if (typeof at !== "number") return [];
        const title = row.title ?? row.label ?? row.kind;
        const category = row.category ?? row.kind;
        return [
          {
            key: `${frameIndex}:${index}`,
            at,
            ends: typeof row.ends_at === "number" ? row.ends_at : null,
            title: title == null ? "Event" : String(title),
            category: category == null ? null : String(category),
            severity: row.severity == null ? null : String(row.severity),
          },
        ];
      }),
    )
    .sort((a, b) => b.at - a.at);
}

export type StateLane = {
  key: string;
  label: string;
  segments: Array<{
    key: string;
    state: string;
    from: number;
    to: number;
    limit: LimitState | null;
  }>;
};

/** Observations become segments that last until the next observation (or now). */
export function stateLanes(placement: WorkspacePlacement, now: number): StateLane[] {
  return primaryFrames(placement)
    .filter((frame) => frame.fields.some((f) => f.name === "normalized_state"))
    .map((frame, frameIndex) => {
      const rows = frameRows(frame)
        .filter((row) => typeof row.time === "number")
        .sort((a, b) => Number(a.time) - Number(b.time));
      const label =
        rows.find((row) => row.label ?? row.observable_id)?.label ?? rows[0]?.observable_id;
      return {
        key: String(frameIndex),
        label: label == null ? `Lane ${frameIndex + 1}` : String(label),
        segments: rows.map((row, index) => {
          const state = row.normalized_state == null ? "unknown" : String(row.normalized_state);
          return {
            key: String(index),
            state,
            from: Number(row.time),
            to: Number(rows[index + 1]?.time ?? now),
            limit: asLimitState(row.limit_state ?? row.normalized_state),
          };
        }),
      };
    });
}

export type HealthCell = { id: string; state: LimitState | "no_data" };

export function constellation(placement: WorkspacePlacement): HealthCell[] {
  return primaryFrames(placement).flatMap((frame) =>
    frameRows(frame).flatMap((row) =>
      typeof row.spacecraft_id === "string"
        ? [{ id: row.spacecraft_id, state: asLimitState(row.worst_state) ?? "no_data" }]
        : [],
    ),
  );
}
