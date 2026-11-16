import type { LocationQuery } from "vue-router";

/** ux U69 A6: the Alarms filter row, in the URL (?sc=, ?severity=), applied by the server. */
export type Severity = "critical" | "caution";
export const SEVERITIES: readonly Severity[] = ["critical", "caution"];
export const SEVERITY_WORDS = { critical: "Critical", caution: "Caution" } as const;
export type EpisodeFilters = Readonly<{ spacecraftId: string | null; severity: Severity | null }>;
export const NO_FILTERS: EpisodeFilters = { spacecraftId: null, severity: null };

const isSeverity = (s: string): s is Severity => (SEVERITIES as readonly string[]).includes(s);

/** The severities ticked in ?severity= (comma-separated; unknown words ignored). */
export function severitiesOf(query: LocationQuery): Severity[] {
  const raw = query.severity;
  const text = typeof raw === "string" ? raw : "";
  return SEVERITIES.filter((s) => text.split(",").filter(isSeverity).includes(s));
}

/** Both ticked is the same as none: the server takes one severity or all. */
export function filtersOf(query: LocationQuery): EpisodeFilters {
  const ticked = severitiesOf(query);
  return {
    spacecraftId: typeof query.sc === "string" && query.sc ? query.sc : null,
    severity: ticked.length === 1 ? (ticked[0] ?? null) : null,
  };
}

export const filtered = (f: EpisodeFilters) => f.spacecraftId !== null || f.severity !== null;

/** The query with one filter changed; empty values leave the URL. */
export function withFilter(
  query: LocationQuery,
  key: "sc" | "severity",
  value: string | null,
): LocationQuery {
  const { [key]: _drop, ...rest } = query;
  return value ? { ...rest, [key]: value } : rest;
}
