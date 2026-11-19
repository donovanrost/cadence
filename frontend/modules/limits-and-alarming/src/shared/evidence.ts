import { text } from "./contracts";

type Row = Record<string, unknown>;
/** The query of `href` when it has exactly `keys`, each once; null otherwise. */
function exactQuery(search: string, keys: readonly string[]): URLSearchParams | null {
  const q = new URLSearchParams(search);
  const seen = [...q.keys()];
  return seen.length === keys.length && keys.every((k) => q.getAll(k).length === 1) ? q : null;
}
/**
 * An org or mission slug: one path segment. Organization slugs have no server-side format, so this
 * is loose, but a segment can't start with "." or "%", so "..", "%2e%2e" and the like can't climb out.
 */
const slug = "[A-Za-z0-9_~-][A-Za-z0-9._~%-]*";
const fleet = new RegExp(`^/console/${slug}/${slug}/fleet/\\d+/telemetry$`);
const telemetry = new RegExp(`^/console/${slug}/${slug}/telemetry$`);

/**
 * api D2: the console's Investigate link (AlarmProvenance's), or its fallbacks. `at` is the sample's
 * generation time, else its receipt time, like an alarm trigger's (the plot's axis is generation).
 */
function consoleLink(href: string, v: Row): boolean {
  if (href === "/console") return true;
  const [path = "", search = "", ...rest] = href.split("?");
  if (rest.length) return false;
  if (fleet.test(path)) {
    const q = exactQuery(search, ["points", "focus", "at"]);
    return (
      q !== null &&
      q.get("points") === v.point_id &&
      q.get("focus") === v.point_id &&
      q.get("at") === (v.generation_time ?? v.receipt_time)
    );
  }
  if (telemetry.test(path)) return exactQuery(search, ["p"])?.get("p") === v.point_id;
  return false;
}

/** A row's `evidence_href` names the row's own point and receipt time, and nothing else. */
export function evidence(v: Row): boolean {
  const href = v.evidence_href;
  if (!text(href, 4096) || /[\\#]/.test(href) || href.split("").some((c) => c.charCodeAt(0) <= 32))
    return false;
  return consoleLink(href, v);
}
