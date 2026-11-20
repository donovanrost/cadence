import { codeOf, fieldErrors, isError, type ApiError } from "@/api/index.ts";
import type { ConfigurationDocument, ConfigurationSnapshot, Protocol } from "./api.ts";
import { apidsWord, catalogWord, framingWord, sourceWord } from "./words.ts";

/** ux U94 (#595a): the words for saving a spacecraft's configuration draft. */

/** "Saved as v4. v3 stays active until v4 is activated." / first: "… Nothing runs until …". */
export function savedLine(s: ConfigurationSnapshot): string {
  const v = s.saved_version === null ? "the draft" : `v${s.saved_version}`;
  const head = s.saved_version === null ? "Saved." : `Saved as ${v}.`;
  if (s.active === null) return `${head} Nothing runs until it's activated.`;
  // U94: an active version 0 (set before this workspace) has no number (mms-ux, #595a).
  const active = s.active.version > 0 ? `v${s.active.version}` : "The current configuration";
  return `${head} ${active} stays active until ${v} is activated.`;
}

export type ConflictRow = Readonly<{ key: string; label: string; saved: string; mine: string }>;

/** U94 "Someone saved…" rows: "Saved: TM → Yours: AOS", only where the two differ. */
export function conflictRows(
  s: ConfigurationSnapshot,
  saved: ConfigurationDocument,
  mine: ConfigurationDocument,
): readonly ConflictRow[] {
  const rows: ConflictRow[] = [
    {
      key: "catalog",
      label: "Catalog revision",
      saved: catalogWord(s, saved.catalog_revision_id),
      mine: catalogWord(s, mine.catalog_revision_id),
    },
    {
      key: "source",
      label: "Packet source",
      saved: sourceWord(s, saved.telemetry_source_endpoint_id),
      mine: sourceWord(s, mine.telemetry_source_endpoint_id),
    },
    {
      key: "apids",
      label: "Handled APIDs",
      saved: apidsWord(saved.handled_apids),
      mine: apidsWord(mine.handled_apids),
    },
    {
      key: "framing",
      label: "Framing",
      saved: framingWord(saved.protocol),
      mine: framingWord(mine.protocol),
    },
  ];
  // compared-as-text: two renderings of the same setting; a difference is what the panel shows
  return rows.filter((r) => r.saved !== r.mine);
}

export const discardQuestion = (s: ConfigurationSnapshot) =>
  s.saved_version === null
    ? "Discard your edits? Nothing has been saved yet."
    : "Discard your edits? The saved draft stays as it is.";

export const leaveBody = (craft: string) => `Your edits to ${craft}'s configuration aren't saved.`;

/** The preset whose framing matches exactly; null reads "Custom" (mms-ux, #595a). */
export function presetOf(s: ConfigurationSnapshot, p: Protocol | null): string | null {
  if (!p) return null;
  const key = JSON.stringify(p);
  return s.presets.find((x) => JSON.stringify(x.protocol) === key)?.id ?? null;
}

export type SaveRefusal = Readonly<{
  text: string;
  /** A code the console doesn't word, for Technical details (U20). */
  code?: string;
  /** U94: `Open profile` (spacecraft_catalog_set_by_profile), when the snapshot names one. */
  openProfile?: true;
  /** Server field errors by the document's field (U94: under their field). */
  fields: Readonly<Record<string, string>>;
}>;

/** "document.handled_apids" → "handled_apids"; "document.protocol.frame_size" → "frame_size". */
const fieldOf = (path: string) => path.replace(/^document\./, "").replace(/^protocol\./, "");

/** U94's save refusals, "Not saved: …" (the bar's place). The stale token is the conflict panel. */
export function saveRefusal(
  e: ApiError,
  s: ConfigurationSnapshot,
  doc: ConfigurationDocument,
): SaveRefusal {
  const craft = s.name;
  const rev = catalogWord(s, doc.catalog_revision_id);
  const plain = (text: string) => ({ text, fields: {} });
  if (isError(e, "spacecraft_catalog_set_by_profile"))
    return {
      ...plain(
        `Not saved: ${craft}'s profile sets its catalog revision. Change it on the profile, through Setup › Changes.`,
      ),
      openProfile: true,
    };
  if (isError(e, "spacecraft_packet_input_unavailable"))
    return plain(
      `Not saved: the packet source you chose isn't available to ${craft} any more. Choose another.`,
    );
  if (isError(e, "spacecraft_configuration_catalog_not_loaded"))
    return plain(
      `Not saved: Cadence couldn't load ${rev}'s telemetry packets. Try again, or choose another revision.`,
    );
  if (isError(e, "spacecraft_catalog_unavailable"))
    return plain(
      `Not saved: ${rev} isn't one of this mission's catalog revisions. Choose another.`,
    );
  if (isError(e, "spacecraft_source_limit_exceeded"))
    return plain(
      `${craft} has more packet sources than one configuration can carry, so it can't be shown or sent. Remove some in Setup › Comms.`,
    );
  if (isError(e, "spacecraft_not_found")) return plain("This spacecraft isn't on this mission.");
  if (e.kind === "forbidden") return plain(`You can't change ${craft}'s configuration.`);
  if (e.kind === "invalid") {
    const fields = fieldErrors(e, fieldOf);
    return Object.keys(fields).length > 0
      ? // U94: invalid_params is the field's own error, under its field; the bar keeps "Not saved."
        { text: "Not saved.", fields }
      : plain("Not saved: Cadence couldn't read this draft. Reload and try again.");
  }
  const code = codeOf(e);
  return code ? { text: "Not saved.", code, fields: {} } : plain("Not saved.");
}

/**
 * Why the Add APID select is off (A6), from the packets read: no catalog revision yet, loading, or
 * U94's picker refusals; null when the packets are there.
 */
export function packetsOffReason(
  s: ConfigurationSnapshot,
  doc: ConfigurationDocument,
  read: Readonly<{ status: "loading" | "ready" | "failed"; code?: string | null }>,
): string | null {
  if (!doc.catalog_revision_id) return "Choose a catalog revision first.";
  if (read.status === "loading") return "Loading the catalog revision's packets…";
  if (read.status === "ready") return null;
  if (read.code === "catalog_revision_not_found")
    return "This catalog revision isn't in the mission's catalog any more. Choose another.";
  const rev = catalogWord(s, doc.catalog_revision_id);
  if (read.code === "spacecraft_catalog_unavailable")
    return `${rev.charAt(0).toUpperCase()}${rev.slice(1)} can't be used for ${s.name}.`;
  return `Cadence couldn't load ${rev}'s packets. Reload to try again.`;
}
