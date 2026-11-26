import { isKnown } from "@/api/index.ts";
import type { Preview, PreviewItem } from "./actions.ts";
import type { HoldReason } from "./preview.ts";

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

/** ux U81 §1: one other spacecraft, 'both'; a folded item standing for two or more missions, 'these'. */
function scidPlaceholder(item: PreviewItem): string {
  const scid = item.details?.scid;
  const id = scid == null ? "this SCID" : `SCID ${scid}`;
  return (item.details?.mission_count ?? 1) >= 2
    ? `Why it's safe for these spacecraft to share ${id}`
    : `Why it's safe for both spacecraft to use ${id}`;
}

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
    case "scid_shared_in_organization":
      return scidPlaceholder(item);
    // Reasons with no placeholder of their own (blocking, or worded elsewhere), and any other.
    case "telemetry_app_not_installed":
    case "derived_point_in_use":
    case "framing_unverified":
    case "framing_mismatch":
    case "mission_model_not_approved":
    case "catalog_command_in_flight":
    case "catalog_configuration_pending":
    case "catalog_change":
    case "catalog_cancels_commands":
    case null:
    case undefined:
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

/**
 * U63: an app a HOLD says to install first, with how many spacecraft need it and the first few by
 * name (the server's `spacecraft_count`/`spacecraft_sample`, #796; one per app).
 */
export type AppHold = Readonly<{
  appKey: string;
  appName: string | null;
  spacecraftCount: number;
  spacecraftSample: readonly Readonly<{ id: string; name: string }>[];
}>;

/** How many names an app hold shows before saying "and N more". */
const SAMPLE_SHOWN = 5;

/** U63: holds that name an app to install (telemetry_app_not_installed), merged per app. */
export function appHolds(preview: Preview): readonly AppHold[] {
  const byKey = new Map<
    string,
    { appName: string | null; count: number; sample: Map<string, string> }
  >();
  for (const c of preview.checks)
    for (const i of c.items) {
      const key = i.reason === "telemetry_app_not_installed" ? i.details?.app_key : null;
      if (!key) continue;
      const entry = byKey.get(key) ?? {
        appName: i.details?.app_name ?? null,
        count: 0,
        sample: new Map<string, string>(),
      };
      // An item for one craft may carry only its entity; a fleet item carries the count and sample.
      const sample =
        i.spacecraft_sample ??
        (i.entity_id ? [{ id: i.entity_id, name: i.entity_name ?? i.entity_id }] : []);
      entry.count += i.spacecraft_count ?? sample.length;
      for (const craft of sample) entry.sample.set(craft.id, craft.name);
      byKey.set(key, entry);
    }
  return [...byKey.entries()].map(([appKey, e]) => ({
    appKey,
    appName: e.appName,
    spacecraftCount: e.count,
    spacecraftSample: [...e.sample]
      .map(([id, name]) => ({ id, name }))
      .sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id))
      .slice(0, SAMPLE_SHOWN),
  }));
}

/** U63: a check whose every item is one titled reason reads as that title (ux). */
const REASON_TITLES: Readonly<Partial<Record<HoldReason, string>>> = {
  telemetry_app_not_installed: "Telemetry app not installed",
  // U65.
  mission_model_not_approved: "Catalog revision not approved",
};
export function checkTitle(items: readonly PreviewItem[]): string | null {
  const [first] = items;
  const title = first?.reason && isKnown(first.reason) ? REASON_TITLES[first.reason] : undefined;
  return title && items.every((i) => i.reason === first?.reason) ? title : null;
}

/** U65: a catalog revision a HOLD says must be approved first (one per model revision). */
export type ModelHold = Readonly<{ revisionId: string; catalogRevisionNumber: number | null }>;

/** U65: mission_model_not_approved holds, once per model revision, for 'Open rev 4'. */
export function modelHolds(preview: Preview): readonly ModelHold[] {
  const byId = new Map<string, number | null>();
  for (const c of preview.checks)
    for (const i of c.items) {
      const id =
        i.reason === "mission_model_not_approved" ? i.details?.mission_model_revision_id : null;
      if (id) byId.set(id, i.details?.catalog_revision_number ?? null);
    }
  return [...byId.entries()].map(([revisionId, catalogRevisionNumber]) => ({
    revisionId,
    catalogRevisionNumber,
  }));
}
