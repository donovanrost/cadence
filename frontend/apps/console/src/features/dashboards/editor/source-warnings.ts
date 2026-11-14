import { isKnown } from "@/api";
import { formatClock } from "@/ui";
import type { LOGICAL_SOURCES, REALMS, SourceWarning } from "./contracts.ts";

/**
 * A successful save's source warnings as sentences (ux words pending): the save went through,
 * but a source wasn't answering, so some widgets may stay empty. One sentence per source.
 */
const SOURCE_WORD: Readonly<Record<(typeof LOGICAL_SOURCES)[number], string>> = {
  telemetry: "Telemetry",
  events: "Events",
  limits: "Limits",
  operational_observables: "Operational data",
};
const REALM_WORD: Readonly<Record<(typeof REALMS)[number], string>> = {
  flight: "flight",
  rehearsal: "rehearsal",
  replay: "replay",
  simulation: "simulation",
};

function sourceName(w: SourceWarning): string {
  const source = isKnown(w.logical_source) ? SOURCE_WORD[w.logical_source] : "A data source";
  const realm = w.realm !== null && isKnown(w.realm) ? ` (${REALM_WORD[w.realm]})` : "";
  return `${source}${realm}`;
}

export function warningText(w: SourceWarning): string {
  const at = w.observed_at ? ` at ${formatClock(new Date(w.observed_at)).slice(0, 5)}Z` : "";
  const n = w.placement_ids.length;
  const widgets = n === 1 ? "1 widget" : `${n} widgets`;
  if (w.code === "source_degraded")
    return `${sourceName(w)} was answering slowly${at}; ${widgets} may show partial data.`;
  if (w.code === "source_unavailable")
    return `${sourceName(w)} wasn't answering${at}; ${widgets} may stay empty until it does.`;
  return w.message;
}

/** "Saved." / "Copied." / "Restored." plus a sentence per warning; null when there are none. */
export function warningsText(lead: string, warnings: readonly SourceWarning[] | undefined) {
  return warnings?.length ? [lead, ...warnings.map(warningText)].join(" ") : null;
}
