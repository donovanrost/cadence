import type { GanttBar, GanttRow } from "@/ui";
import type { Pass } from "./api.ts";

/** Passes → ApGantt rows (stations) and bars (contacts), for Now A4 and Contacts J4. */

/** Station label: the Cadence code, else the provider's ref (contract: show `ref` when unmatched). */
export const stationLabel = (p: Pass) => p.station.code ?? p.station.ref ?? "—";
const stationKey = (p: Pass) => p.station.id ?? p.station.ref ?? "unknown";

export type PassStatus = "live" | "scheduled" | "done" | "problem" | "canceled";

/** A client reading of the three provider fields (contract: the UI decodes them). */
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
  nameOf: (spacecraftId: string) => { name: string; scid: number } | null,
  now: number,
  selected: string | null = null,
  axis: GanttAxis = "station",
): { rows: GanttRow[]; bars: GanttBar[] } {
  const rows = new Map<string, GanttRow>();
  const bars: GanttBar[] = [];
  for (const p of passes) {
    const kind = KIND[passStatus(p, now)];
    if (kind === null) continue;
    const sc = p.spacecraft_id ? nameOf(p.spacecraft_id) : null;
    const key = axis === "station" ? stationKey(p) : (p.spacecraft_id ?? "unknown");
    const rowLabel = axis === "station" ? stationLabel(p) : (sc?.name ?? p.spacecraft_id ?? "—");
    if (!rows.has(key)) rows.set(key, { id: key, label: rowLabel });
    const status = passStatus(p, now);
    bars.push({
      id: p.id,
      rowId: key,
      from: Date.parse(p.starts_at),
      to: Date.parse(p.ends_at),
      kind: selected === p.id ? "focused" : kind,
      label:
        axis === "station" ? (sc ? String(sc.scid).padStart(3, "0") : undefined) : stationLabel(p),
      description: `${sc?.name ?? "Unknown spacecraft"} at ${p.station.name ?? stationLabel(p)}, ${status}${p.source.synthetic ? " (synthetic window)" : ""}`,
    });
  }
  return { rows: [...rows.values()].sort((a, b) => a.label.localeCompare(b.label)), bars };
}
