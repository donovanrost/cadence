import { isKnown } from "@/api";
import { formatHourMinute, formatShort } from "@/ui";
import type { LOGICAL_SOURCES, REALMS, SourceWarning } from "./contracts.ts";

/**
 * A successful write's source warnings as sentences (ux, Dashboards.md › Edit in place): the
 * write went through, but a source wasn't answering when its health was checked, so some widgets
 * may stay empty. One sentence per source.
 */
const SOURCE_WORD: Readonly<Record<(typeof LOGICAL_SOURCES)[number], string>> = {
  telemetry: "Telemetry",
  events: "Events",
  limits: "Limits",
  operational_observables: "Operational data",
};
/** Flight is the normal realm, so it goes unnamed (ux). */
const REALM_WORD: Readonly<Record<(typeof REALMS)[number], string | null>> = {
  flight: null,
  rehearsal: "rehearsal",
  replay: "replay",
  simulation: "simulation",
};

function sourceName(w: SourceWarning): string {
  const source = isKnown(w.logical_source) ? SOURCE_WORD[w.logical_source] : "A data source";
  const realm = w.realm !== null && isKnown(w.realm) ? REALM_WORD[w.realm] : null;
  return realm ? `${source} (${realm})` : source;
}

/** observed_at is when health was checked, not when it failed (ux U20); §4 short form. */
function checked(observedAt: string | null, now: Date): string {
  if (!observedAt) return "";
  const at = new Date(observedAt);
  const today = at.toISOString().slice(0, 10) === now.toISOString().slice(0, 10);
  return ` when checked at ${today ? formatHourMinute(at) : formatShort(at)}`;
}

export function warningText(w: SourceWarning, now: Date): string {
  const n = w.placement_ids.length;
  const widgets = n === 1 ? "1 widget" : `${n} widgets`;
  const when = checked(w.observed_at, now);
  if (w.code === "source_degraded")
    return n
      ? `${sourceName(w)} was slow${when}; ${widgets} may load slowly or show partial data.`
      : `${sourceName(w)} was slow${when}.`;
  if (w.code === "source_unavailable")
    return n
      ? `${sourceName(w)} wasn't answering${when}; ${widgets} may stay empty until it does.`
      : `${sourceName(w)} wasn't answering${when}.`;
  return w.message;
}

/** "Saved." / "Copied." / "Restored." plus a sentence per warning; null when there are none. */
export function warningsText(
  lead: string,
  warnings: readonly SourceWarning[] | undefined,
  now: Date = new Date(),
) {
  return warnings?.length ? [lead, ...warnings.map((w) => warningText(w, now))].join(" ") : null;
}
