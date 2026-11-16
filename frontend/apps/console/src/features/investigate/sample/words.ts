import { isKnown, vocabularyText } from "@/api/index.ts";
import type { Sample, SampleRead, SampleValue } from "./api.ts";

/**
 * ux U80: the Sample aside's words. Rows in U80's order, a null name drops its part (U25), and ids
 * only ever appear in Technical details.
 */
export type SampleRow = Readonly<{ key: string; label: string; value: string; mono?: boolean }>;

const pad = (n: number, w = 2) => String(n).padStart(w, "0");
/** §4 with milliseconds: `02:08:11.204Z`, with `11-15 ` in front when not on `today` (YYYY-MM-DD). */
export function sampleTime(iso: string, today: string): string {
  const t = new Date(iso);
  const clock = `${pad(t.getUTCHours())}:${pad(t.getUTCMinutes())}:${pad(t.getUTCSeconds())}.${pad(t.getUTCMilliseconds(), 3)}Z`;
  const day = t.toISOString().slice(0, 10);
  return day === today ? clock : `${day.slice(5)} ${clock}`;
}

/** `1.7 s later` under a minute, then `3 min later` / `2 h later`; null unless after `from`. */
export function laterBy(from: string | null, to: string): string | null {
  if (from === null) return null;
  const s = (Date.parse(to) - Date.parse(from)) / 1000;
  if (!(s > 0)) return null;
  if (s < 60) return `${s.toFixed(1)} s later`;
  if (s < 3600) return `${Math.round(s / 60)} min later`;
  return `${Math.round(s / 3600)} h later`;
}

const valueWords = {
  not_recorded: "Not recorded",
  unsupported: "Can't be shown for this point type",
  limited: "Too large to show here",
} as const;
/** The value line: the text when ready (with the unit for Value, U24), else the state's words. */
export function valueLine(v: SampleValue, unit: string | null = null): string {
  // ux: a state we haven't learned shows its text if any, else "Can't be shown here", never its word.
  if (!isKnown(v.state)) return v.text ?? "Can't be shown here";
  if (v.state !== "ready") return valueWords[v.state];
  if (v.text === null) return "—";
  return unit ? `${v.text} ${unit}` : v.text;
}

const qualityWords = { good: "Good", suspect: "▲ Suspect", bad: "▲ Bad" } as const;
const recordWords = {
  canonical: "The record Cadence uses",
  duplicate: "A duplicate: Cadence uses another copy",
  conflict: "▲ Conflicts with another record for this time",
  superseded: "Replaced by a later revision",
  advisory: "Kept for reference: not the record Cadence uses",
} as const;

/** Packet: `HK_EPS v4`; an unnamed definition still says it has a version. */
function packetLine(r: Sample["record"]): string | null {
  const v = r.packet_definition_version === null ? "" : ` v${r.packet_definition_version}`;
  if (r.packet_definition_name) return `${r.packet_definition_name}${v}`;
  return r.packet_definition_id ? `An unnamed packet definition${v}` : null;
}

/** Came in through: endpoint, then binding; else the data source's name; else no row (U80). */
export function cameInThrough(s: Sample["source"]): string | null {
  const version = s.binding_version === null ? "" : ` v${s.binding_version}`;
  const parts = [s.endpoint_label, s.binding_label ? `binding ${s.binding_label}${version}` : null];
  const named = parts.filter((p): p is string => p !== null);
  return named.length ? named.join(" · ") : s.data_source_name;
}

/** Realm: no row for flight; `Replay · run 14` names the run when its label resolves. */
export function realmLine(s: Sample["source"]): string | null {
  if (!isKnown(s.realm)) return s.realm.unrecognized;
  if (s.realm === "flight") return null;
  if (s.realm === "replay")
    return s.replay_run_label ? `Replay · run ${s.replay_run_label}` : "Replay";
  return s.realm === "rehearsal" ? "Rehearsal" : "Simulation";
}

export function sampleRows(s: Sample, today: string): SampleRow[] {
  const rows: (SampleRow | null)[] = [
    {
      key: "value",
      label: "Value",
      value: valueLine(s.engineering_value, s.engineering_unit),
      mono: true,
    },
    { key: "raw", label: "Raw", value: valueLine(s.raw_value), mono: true },
    { key: "quality", label: "Quality", value: vocabularyText(s.quality, qualityWords) },
    s.generation_time
      ? {
          key: "generated",
          label: "Generated",
          value: sampleTime(s.generation_time, today),
          mono: true,
        }
      : null,
    {
      key: "received",
      label: "Received",
      value: [sampleTime(s.receipt_time, today), laterBy(s.generation_time, s.receipt_time)]
        .filter((p): p is string => p !== null)
        .join(" · "),
      mono: true,
    },
  ];
  const packet = packetLine(s.record);
  if (packet) rows.push({ key: "packet", label: "Packet", value: packet });
  if (s.record.validity_state !== null)
    rows.push({
      key: "record",
      label: "Record",
      value: vocabularyText(s.record.validity_state, recordWords),
    });
  const through = cameInThrough(s.source);
  if (through) rows.push({ key: "through", label: "Came in through", value: through });
  const realm = realmLine(s.source);
  if (realm) rows.push({ key: "realm", label: "Realm", value: realm });
  return rows.filter((r): r is SampleRow => r !== null);
}

/** True for the rows ux marks as caution (Suspect/Bad quality, a conflicting record). */
export const cautionRow = (r: SampleRow) => r.value.startsWith("▲");

/** Technical details: every id, then the full JSON or hex of a formatted value. */
export function technicalRows(s: Sample): SampleRow[] {
  const ids: [string, string, string | null][] = [
    ["sample", "Sample id", s.sample_id],
    ["point", "Point id", s.point_id],
    ["packet", "Packet id", s.record.packet_id],
    ["evidence", "Evidence id", s.record.evidence_id],
    ["definition", "Packet definition id", s.record.packet_definition_id],
    ["source", "Data source id", s.source.data_source_id],
    ["binding", "Binding id", s.source.source_binding_id],
    ["endpoint", "Endpoint id", s.source.source_endpoint_id],
    ["run", "Replay run id", s.source.replay_run_id],
  ];
  const full = (key: string, label: string, v: SampleValue) =>
    v.format !== null && v.text !== null ? [{ key, label, value: v.text, mono: true }] : [];
  return [
    ...ids.flatMap(([key, label, value]) => (value ? [{ key, label, value, mono: true }] : [])),
    ...full("raw-full", "Raw (full)", s.raw_value),
    ...full("value-full", "Value (full)", s.engineering_value),
  ];
}

/** The aside's body when the read isn't ready (U80 statuses); `at` is `02:08:11Z`. */
export type StatusView = Readonly<{ line: string; action: "retry" | "show-at" | null }>;
export function statusView(status: SampleRead["status"], at: string | null): StatusView | null {
  if (!isKnown(status)) return { line: "Cadence couldn't read this sample.", action: "retry" };
  switch (status) {
    case "ready":
      return null;
    case "not_found":
      return { line: "Cadence couldn't find this sample in the history store.", action: null };
    case "ambiguous":
      return {
        line: `More than one sample matches ${at ?? "this time"}, so Cadence can't tell which one this is.`,
        action: at ? "show-at" : null,
      };
    case "timeout":
      return { line: "Reading the sample took too long.", action: "retry" };
    case "unsupported":
      return { line: "This data source can't look up a single sample.", action: null };
    case "unavailable":
      return { line: "The history store can't be reached right now.", action: "retry" };
  }
}
