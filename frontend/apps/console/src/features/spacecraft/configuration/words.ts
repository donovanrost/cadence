import { vocabularyText } from "@/api/index.ts";
import type { OpState } from "@/ui";
import type { ConfigurationDocument, ConfigurationSnapshot, SwitchState } from "./api.ts";

/**
 * ux U94 words for a spacecraft's configuration workspace. Never in visible text: generation,
 * binding, token, ids (Technical details only). Versions read v4, never r4 (a change-set revision).
 */

/** "v4"; a version of 0 (set before this workspace) has no number (U94). */
export const versionWord = (v: number) => (v > 0 ? `v${v}` : "");

const same = (a: ConfigurationDocument, b: ConfigurationDocument) =>
  JSON.stringify(a) === JSON.stringify(b);

/** True while the saved draft differs from what's active (or nothing is active yet). */
export function draftDiffers(s: ConfigurationSnapshot): boolean {
  return s.saved_version !== null && (s.active === null || !same(s.document, s.active.document));
}

/** The section header's tag: NOT SET UP / DRAFT SAVED · v4 (caution) / ACTIVE · v3. */
export function statusTag(s: ConfigurationSnapshot): Readonly<{ label: string; state: OpState }> {
  if (s.saved_version !== null && draftDiffers(s))
    return { label: `Draft saved · v${s.saved_version}`, state: "caution" };
  if (s.active === null) return { label: "Not set up", state: "off" };
  const v = versionWord(s.active.version);
  return { label: v ? `Active · ${v}` : "Active", state: "nominal" };
}

/** U94 "Steps before it can be sent" (the host's setup issues), in the console's words. */
export function setupSteps(
  doc: ConfigurationDocument,
  craft: string,
): readonly Readonly<{ key: "catalog" | "decode"; label: string; detail: string }>[] {
  const steps: { key: "catalog" | "decode"; label: string; detail: string }[] = [];
  if (!doc.catalog_revision_id)
    steps.push({
      key: "catalog",
      label: "Choose a catalog revision",
      detail: `Pick the catalog revision that matches ${craft}'s flight software.`,
    });
  if (doc.telemetry_enabled && (!doc.telemetry_source_endpoint_id || !doc.handled_apids.length))
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
/** "TM ↓ / TC ↑ · 1,115 B frames · headers 0/0/4 B" (protocol terms stay, U94). */
export function framingWord(p: ConfigurationDocument["protocol"]): string {
  if (!p) return "Not set";
  const down = vocabularyText(p.downlink, LINK);
  const up = vocabularyText(p.uplink, LINK);
  const truncated = p.truncated_primary_header ? " · truncated primary header" : "";
  return `${down} ↓ / ${up} ↑ · ${p.frame_size.toLocaleString("en-US")} B frames · headers ${p.secondary_header_length}/${p.insert_zone_length}/${p.ocf_length} B${truncated}`;
}

/**
 * DECISIONS #109 (U94): change sets own both switches. "On · set by r7." / "Off · no change set has
 * turned it on yet. …"; without the snapshot's switches (an older server), the value alone.
 */
export function switchLine(sw: SwitchState | undefined, value: boolean, craft: string): string {
  const on = (sw?.value ?? value) ? "On" : "Off";
  if (!sw) return on;
  if (!sw.set)
    return `Off · no change set has turned it on yet. Turn it on in ${craft}'s Operation panel; it applies with the next change set.`;
  return sw.revision !== null
    ? `${on} · set by r${sw.revision}.`
    : `${on} · set through Setup › Changes.`;
}

export type ComparisonRow = Readonly<{ setting: string; active: string; draft: string }>;
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
    },
    {
      setting: "Framing",
      active: a ? framingWord(a.protocol) : "—",
      draft: framingWord(d.protocol),
    },
  ];
  return a ? rows.filter((r) => r.active !== r.draft) : rows;
}

export const NOTHING_ACTIVE = "Nothing is active yet, so every setting is new.";
export const DRAFT_MATCHES = "The draft matches the active configuration.";

/** U94 "Not set up": the info line under "Set up EARENDIL-004". */
export const notSetUpLine = (craft: string) =>
  `Nothing runs for ${craft} until its configuration is activated.`;
