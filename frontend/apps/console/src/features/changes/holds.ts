import type { Preview, PreviewItem } from "./actions.ts";

/**
 * Acknowledgeable HOLDs (ux U40, U41, U43): the Apply 'Why' placeholder says what to justify, and a
 * limits HOLD links to its point's alarms.
 */
function acknowledgeable(preview: Preview): readonly PreviewItem[] {
  return preview.checks
    .filter((c) => c.verdict === "hold" && c.blocking !== true)
    .flatMap((c) => c.items.filter((i) => i.blocking !== true));
}

/** Retiring (not editing) the limits a HOLD is about: a delete of that entity in the set. */
const retiring = (item: PreviewItem, preview: Preview) =>
  (preview.diffs ?? []).some(
    (d) => d.kind === "limit_definition" && d.entity_id === item.entity_id && d.action === "delete",
  );

function placeholderFor(item: PreviewItem, preview: Preview): string | null {
  const name = item.entity_name ?? "this spacecraft";
  switch (item.reason) {
    case "spacecraft_passes_booked":
      return "Why the passes stay booked";
    case "spacecraft_has_traffic":
      return `Why ${name} is being archived`;
    case "commanding_disabled_cancels_commands":
      return "Why it's safe to cancel them";
    case "telemetry_disabled":
      return `Why decoding can stop for ${name}`;
    case "handled_apids_change":
      return "Why this change is intended";
    case "limit_alarm_active":
      return retiring(item, preview)
        ? "Why it's safe to clear it"
        : "Why it's safe to change them while it's raised";
    default:
      return null;
  }
}

/** One acknowledgeable HOLD: its own placeholder; several: the general one; none: null. */
export function whyPlaceholder(preview: Preview): string | null {
  const holds = acknowledgeable(preview);
  const [only] = holds;
  if (!only) return null;
  return holds.length === 1
    ? placeholderFor(only, preview)
    : "Why it's safe to apply despite these holds";
}

/** U43: the points with a limit alarm raised now, once each, for 'Open in Alarms' (?point=). */
export function alarmPoints(preview: Preview): readonly string[] {
  const points = preview.checks.flatMap((c) =>
    c.items.flatMap((i) =>
      i.reason === "limit_alarm_active" && i.details?.point_id ? [i.details.point_id] : [],
    ),
  );
  return [...new Set(points)];
}
