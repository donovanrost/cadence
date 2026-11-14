import type { Scid, SpacecraftId } from "@/api/index.ts";
import { readinessTag } from "./readiness.ts";
import { passAttentionDescription, passAttentionTag } from "./passAttention.ts";
import type { GanttBand, GanttBar, GanttRow } from "@/ui";
import type { Availability } from "@/features/scheduling/index.ts";
import type { Pass } from "./api.ts";

/** Passes → ApGantt rows (stations) and bars (contacts), for Now A4 and Contacts J4. */

/** Station label: the Cadence code, else the provider's ref (contract: show `ref` when unmatched). */
export const stationLabel = (p: Pass) => p.station.code ?? p.station.ref ?? "—";
const stationKey = (p: Pass) => p.station.id ?? p.station.ref ?? "unknown";

export type PassStatus = "live" | "scheduled" | "done" | "problem" | "canceled";

/** A client reading of the three provider fields (contract: the UI decodes them). */
/** U32 evidence in a bar's description: whose word the booking rests on, and an unconfirmed uplink. */
function evidence(p: Pass): string {
  const attested =
    p.booking_evidence === "operator_attested"
      ? `, booked on the word of ${p.attested_by?.name ?? "an operator"}`
      : "";
  const ready = p.uplink_readiness
    ? readinessTag(p.uplink_readiness, "row", { provider: p.source.provider_name })
    : null;
  return `${attested}${p.uplink_confirmed === false ? ", uplink unconfirmed" : ""}${ready ? `, ${(ready.sentence ?? ready.label).replace(/[.]$/, "").toLowerCase()}` : ""}${passAttentionDescription(p)}`;
}

export function passStatus(p: Pass, now: number): PassStatus {
  if (p.state === "rejected" || p.state === "failed" || p.state === "unknown") return "problem";
  if (p.state === "canceled" || p.state === "canceling") return "canceled";
  if (p.state === "active" || p.pass_phase === "pass") return "live";
  if (p.state === "completed" || Date.parse(p.ends_at) < now) return "done";
  return "scheduled";
}

const KIND: Readonly<Record<PassStatus, GanttBar["kind"] | null>> = {
  live: "live",
  scheduled: "scheduled",
  problem: "problem",
  done: "done",
  canceled: null,
};

/** Row axis: stations (default) or spacecraft (Contacts "By spacecraft"). */
export type GanttAxis = "station" | "spacecraft";

export function passGantt(
  passes: readonly Pass[],
  nameOf: (spacecraftId: SpacecraftId) => { name: string; scid: Scid | null } | null,
  now: number,
  selected: string | null = null,
  axis: GanttAxis = "station",
  /**
   * D3 header chips (Contacts.md): `match` highlights one spacecraft's passes in place (the rest
   * dim, never hidden); `uplinks` notches bars with command requests queued on them.
   */
  marks: Readonly<{ match?: ((p: Pass) => boolean) | null; uplinks?: ReadonlySet<string> }> = {},
): { rows: GanttRow[]; bars: GanttBar[] } {
  const rows = new Map<string, GanttRow>();
  const bars: GanttBar[] = [];
  for (const p of passes) {
    const kind = KIND[passStatus(p, now)];
    if (kind === null) continue;
    const sc =
      (p.spacecraft_id ? nameOf(p.spacecraft_id) : null) ??
      (p.spacecraft ? { name: p.spacecraft.name, scid: p.spacecraft.scid } : null);
    const key = axis === "station" ? stationKey(p) : (p.spacecraft_id ?? "unknown");
    // A spacecraft the fleet doesn't know is still identified, never by a truncated raw id.
    const rowLabel = axis === "station" ? stationLabel(p) : (sc?.name ?? "Unknown spacecraft");
    if (!rows.has(key)) rows.set(key, { id: key, label: rowLabel });
    const status = passStatus(p, now);
    // ux U45: ◆ the top item is a missed pass, ▲ any other open item (lead bf3f36aac).
    const attention = passAttentionTag(p)?.state;
    bars.push({
      id: p.id,
      rowId: key,
      from: Date.parse(p.starts_at),
      to: Date.parse(p.ends_at),
      kind: selected === p.id ? "focused" : kind,
      label:
        axis === "station"
          ? sc?.scid != null
            ? String(sc.scid).padStart(3, "0")
            : undefined
          : stationLabel(p),
      description: `${sc?.name ?? "Unknown spacecraft"} at ${p.station.name ?? stationLabel(p)}, ${status}${evidence(p)}${p.source.synthetic ? " (synthetic window)" : ""}${marks.uplinks?.has(p.id) ? ", uplink queued" : ""}`,
      ...(marks.match && !marks.match(p) ? { dim: true } : {}),
      ...(marks.uplinks?.has(p.id) ? { notch: true } : {}),
      ...(attention ? { attention } : {}),
    });
  }
  return { rows: [...rows.values()].sort((a, b) => a.label.localeCompare(b.label)), bars };
}

/**
 * D3 outage / maintenance / degraded bands (Contacts.md, S7): each uncleared window on a station
 * that has a row (station axis only; K1 draws the same from the same read). An open-ended window
 * runs to the edge of the view.
 */
export function availabilityBands(
  availability: Availability | null,
  rows: readonly GanttRow[],
  windowTo: number,
): GanttBand[] {
  if (!availability) return [];
  const shown = new Set(rows.map((r) => r.id));
  return availability.stations
    .filter((st) => shown.has(st.ground_station_id))
    .flatMap((st) =>
      st.windows
        .filter((w) => w.cleared_at === null)
        .map((w) => ({
          rowId: w.ground_station_id,
          from: Date.parse(w.from),
          to: w.to ? Date.parse(w.to) : windowTo,
          kind: w.kind,
          label: `${w.kind.charAt(0).toUpperCase()}${w.kind.slice(1)}${w.reason ? `: ${w.reason}` : ""}${w.to ? "" : " · no end reported"}`,
        })),
    );
}
