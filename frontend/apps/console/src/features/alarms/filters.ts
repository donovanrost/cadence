import type { LocationQuery } from "vue-router";
import type { Episode } from "./episodes.ts";

/**
 * ux U69 A6: the Alarms filter row, in the URL (?sc=, ?severity=). Applied to the one episodes
 * read, so the picker can count each spacecraft's alarms and the list can say 'N of M shown'.
 */
export type Severity = Episode["severity"];
export const SEVERITIES: readonly Severity[] = ["critical", "caution"];
export const SEVERITY_WORDS = { critical: "Critical", caution: "Caution" } as const;
export type EpisodeFilters = Readonly<{ spacecraftId: string | null; severities: Severity[] }>;

const isSeverity = (s: string): s is Severity => (SEVERITIES as readonly string[]).includes(s);

/** ?sc= and ?severity= (comma-separated; unknown words ignored; both ticked = no filter). */
export function filtersOf(query: LocationQuery): EpisodeFilters {
  const raw = typeof query.severity === "string" ? query.severity.split(",") : [];
  const ticked = SEVERITIES.filter((s) => raw.filter(isSeverity).includes(s));
  return {
    spacecraftId: typeof query.sc === "string" && query.sc ? query.sc : null,
    severities: ticked.length === SEVERITIES.length ? [] : ticked,
  };
}

export const filtered = (f: EpisodeFilters) => f.spacecraftId !== null || f.severities.length > 0;

export const matches = (e: Episode, f: EpisodeFilters) =>
  (f.spacecraftId === null || e.spacecraft_id === f.spacecraftId) &&
  (f.severities.length === 0 || f.severities.includes(e.severity));

/** The query with one filter changed; empty values leave the URL. */
export function withFilter(
  query: LocationQuery,
  key: "sc" | "severity",
  value: string | null,
): LocationQuery {
  const { [key]: _drop, ...rest } = query;
  return value ? { ...rest, [key]: value } : rest;
}

/**
 * ux: the picker lists only spacecraft with alarms in the current tab, each with its count
 * ('EARENDIL-312 (3)'), by name; the selected one stays even at 0.
 */
export function spacecraftOptions(
  episodes: readonly Episode[],
  selected: string | null,
  nameOf: (id: string) => string,
): { value: string; label: string }[] {
  const counts = new Map<string, number>();
  for (const e of episodes)
    if (e.spacecraft_id) counts.set(e.spacecraft_id, (counts.get(e.spacecraft_id) ?? 0) + 1);
  if (selected !== null && !counts.has(selected)) counts.set(selected, 0);
  return [...counts]
    .map(([id, n]) => ({ value: id, label: `${nameOf(id)} (${n})` }))
    .sort((a, b) => a.label.localeCompare(b.label, undefined, { numeric: true }));
}

/** ux (Fleet's form): 'No critical alarms on EARENDIL-312.' / 'No caution alarms.' / 'No alarms on …'. */
export function filteredEmpty(f: EpisodeFilters, nameOf: (id: string) => string): string {
  const sev = f.severities.length === 1 ? `${f.severities[0]} ` : "";
  const on = f.spacecraftId === null ? "" : ` on ${nameOf(f.spacecraftId)}`;
  return `No ${sev}alarms${on}.`;
}

/**
 * 'N of M shown' where the table starts; while more pages remain, the count covers only what's
 * loaded ('· from the 400 loaded', ux U72), and it grows with Load more.
 */
export function shownLine(shown: number, total: number, loaded: number, more: boolean): string {
  const line = `${shown} of ${total} shown`;
  return more ? `${line} · from the ${loaded} loaded` : line;
}
