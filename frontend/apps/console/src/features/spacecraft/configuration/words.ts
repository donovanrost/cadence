import { vocabularyText } from "@/api/index.ts";
import type { OpState } from "@/ui";
import type { ConfigurationDocument, ConfigurationSnapshot, SwitchState } from "./api.ts";

/**
 * ux U94 words for a spacecraft's configuration workspace. Never in visible text: generation,
 * binding, token, ids (Technical details only). Versions read v4, never r4 (a change-set revision).
 */

const same = (a: ConfigurationDocument, b: ConfigurationDocument) =>
  JSON.stringify(a) === JSON.stringify(b);

/** True while the saved draft differs from what's active (or nothing is active yet). */
export function draftDiffers(s: ConfigurationSnapshot): boolean {
  return s.saved_version !== null && (s.active === null || !same(s.document, s.active.document));
}

/** The header's tag, state only (ux U94 (b)): DRAFT SAVED (caution) / NOT SET UP / ACTIVE. */
export function statusTag(s: ConfigurationSnapshot): Readonly<{ label: string; state: OpState }> {
  if (s.saved_version !== null && draftDiffers(s))
    return { label: "Draft saved", state: "caution" };
  if (s.active === null) return { label: "Not set up", state: "off" };
  return { label: "Active", state: "nominal" };
}

/** U94 (b): the versions, mono and lowercase beside the title: "v3 active, v4 saved". */
export function versionsLine(s: ConfigurationSnapshot): string | null {
  const parts = [
    s.active && s.active.version > 0 ? `v${s.active.version} active` : null,
    s.saved_version !== null && draftDiffers(s) ? `v${s.saved_version} saved` : null,
  ].filter((p): p is string => p !== null);
  return parts.length ? parts.join(" · ") : null;
}

/** U94 "Steps before it can be sent" (the host's setup issues), in the console's words. */
export function setupSteps(
  doc: ConfigurationDocument,
  craft: string,
  /** The Telemetry switch's value (#109: from `switches`, never the document). */
  telemetryOn: boolean,
): readonly Readonly<{ key: "catalog" | "decode"; label: string; detail: string }>[] {
  const steps: { key: "catalog" | "decode"; label: string; detail: string }[] = [];
  if (!doc.catalog_revision_id)
    steps.push({
      key: "catalog",
      label: "Choose a catalog revision",
      detail: `Pick the catalog revision that matches ${craft}'s flight software.`,
    });
  if (telemetryOn && (!doc.telemetry_source_endpoint_id || !doc.handled_apids.length))
    steps.push({
      key: "decode",
      label: "Choose what to decode",
      detail: `Pick the packet source and the APIDs Cadence decodes for ${craft}.`,
    });
  return steps;
}

/** "catalog rev 14" (U65); without a number, the row's own name and label. */
export function catalogWord(s: ConfigurationSnapshot, id: string | null | undefined): string {
  if (!id) return "No catalog revision";
  const row = s.catalogs.find((c) => c.id === id);
  if (!row) return "A catalog revision that's no longer listed";
  return row.number !== undefined ? `catalog rev ${row.number}` : `${row.name} · ${row.label}`;
}

export function sourceWord(s: ConfigurationSnapshot, id: string | null | undefined): string {
  if (!id) return "No packet source";
  return s.sources.find((x) => x.id === id)?.name ?? "A packet source that's no longer listed";
}

/** U40's chip list as text: "0x2A, 0x2B". */
export const apidsWord = (apids: readonly number[]) =>
  apids.length
    ? apids.map((a) => `0x${a.toString(16).toUpperCase().padStart(2, "0")}`).join(", ")
    : "None";

const LINK = { tm: "TM", aos: "AOS", uslp: "USLP", tc: "TC" } as const;
/**
 * "TM / TC · 1,115-byte frames · secondary header 0 bytes · insert zone 0 bytes · OCF 4 bytes"
 * (protocol terms stay, U94; no arrows, sizes named, ux #349).
 */
export function framingWord(p: ConfigurationDocument["protocol"]): string {
  if (!p) return "Not set";
  const down = vocabularyText(p.downlink, LINK);
  const up = vocabularyText(p.uplink, LINK);
  const truncated = p.truncated_primary_header ? " · truncated primary header" : "";
  const bytes = (n: number) => `${n.toLocaleString("en-US")} ${n === 1 ? "byte" : "bytes"}`;
  return `${down} / ${up} · ${p.frame_size.toLocaleString("en-US")}-byte frames · secondary header ${bytes(p.secondary_header_length)} · insert zone ${bytes(p.insert_zone_length)} · OCF ${bytes(p.ocf_length)}${truncated}`;
}

/**
 * DECISIONS #109 (U94): change sets own both switches. "On · set by r7." / "Off · no change set has
 * turned it on yet. …" / "On · set through Setup › Changes." (set, revision unknown).
 */
export function switchLine(sw: SwitchState, craft: string): string {
  const on = sw.value ? "On" : "Off";
  if (!sw.set)
    return `Off · no change set has turned it on yet. Turn it on in ${craft}'s Operation panel; it applies with the next change set.`;
  return sw.revision !== null
    ? `${on} · set by r${sw.revision}.`
    : `${on} · set through Setup › Changes.`;
}

export type ComparisonRow = Readonly<{
  setting: string;
  active: string;
  draft: string;
  /** Literal values (APIDs, framing) read in mono, as on the Overview (ux U94). */
  mono?: true;
}>;
/**
 * U94's Changes: Setting / Active / Draft, changed rows only; with nothing active, every setting
 * (Active reads —). The switches never show as a change (#109: the draft takes their values).
 */
export function comparisonRows(s: ConfigurationSnapshot): readonly ComparisonRow[] {
  const a = s.active?.document ?? null;
  const d = s.document;
  const rows: ComparisonRow[] = [
    {
      setting: "Catalog revision",
      active: a ? catalogWord(s, a.catalog_revision_id) : "—",
      draft: catalogWord(s, d.catalog_revision_id),
    },
    {
      setting: "Packet source",
      active: a ? sourceWord(s, a.telemetry_source_endpoint_id) : "—",
      draft: sourceWord(s, d.telemetry_source_endpoint_id),
    },
    {
      setting: "Handled APIDs",
      active: a ? apidsWord(a.handled_apids) : "—",
      draft: apidsWord(d.handled_apids),
      mono: true,
    },
    {
      setting: "Framing",
      active: a ? framingWord(a.protocol) : "—",
      draft: framingWord(d.protocol),
      mono: true,
    },
  ];
  return a ? rows.filter((r) => r.active !== r.draft) : rows;
}

export const NOTHING_ACTIVE = "Nothing is active yet, so every setting is new.";
export const DRAFT_MATCHES = "The draft matches the active configuration.";

/**
 * U94's read refusals, as the section's state (the craft's name isn't known when the read fails).
 * null: anything else, which ApRemote words with Retry.
 */
export function readRefusal(
  code: string | null,
): Readonly<{ text: string; comms: boolean }> | null {
  if (code === "spacecraft_not_found")
    return { text: "This spacecraft isn't on this mission.", comms: false };
  // ux U98 (#272): a 403 on a read says "view", with who grants access. No snapshot, so no name;
  // never the id or a cached name.
  if (code === "forbidden")
    return {
      text: "You can't view this spacecraft's configuration. Ask a mission admin or an org admin for access.",
      comms: false,
    };
  if (code === "spacecraft_source_limit_exceeded")
    return {
      text: "This spacecraft has more packet sources than one configuration can carry, so it can't be shown or sent. Remove some in Setup › Comms.",
      comms: true,
    };
  return null;
}

/**
 * U94 "Not set up": the info line under "Set up EARENDIL-004"; with telemetry off it adds what a new
 * craft needs first (#109: a change set turns telemetry on).
 */
export const notSetUpLine = (craft: string, telemetryOn: boolean) =>
  `Nothing runs for ${craft} until its configuration is activated${telemetryOn ? "" : ", and nothing is decoded until a change set turns telemetry on"}.`;

/** U94: the Draft panel's pointer to Changes, "2 changes from v3"; null when nothing differs. */
export function changesFromLine(s: ConfigurationSnapshot): string | null {
  if (!s.active || !draftDiffers(s)) return null;
  const n = comparisonRows(s).length;
  if (n === 0) return null;
  const v = s.active.version > 0 ? ` from v${s.active.version}` : "";
  return `${n === 1 ? "1 change" : `${n} changes`}${v}`;
}

/** The Changes tab's count (U94): settings that differ, or every setting on a first start. */
export function changesCount(s: ConfigurationSnapshot): number | undefined {
  if (s.active !== null && !draftDiffers(s)) return undefined;
  return comparisonRows(s).length || undefined;
}
