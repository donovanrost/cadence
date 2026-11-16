import { isKnown } from "@/api";
import { reasonText, type HoldReason, type Preview, type PreviewItem } from "./preview.ts";
import { configKindText } from "./shapes.ts";

/**
 * Words for the dry run's check items (split from actions.ts, lead 11-16): each item's line, the
 * conflict and framing sentences, and the holds that block an apply.
 */
/** 1115 → "1,115", with the schema unit when there is one. */
export function valueText(v: unknown, unit?: string | null, format?: string | null): string {
  if (v === null || v === undefined) return "not set";
  if (format === "version" && typeof v === "number") return `v${v}`;
  const text = typeof v === "number" ? v.toLocaleString("en-US") : shown(v);
  return unit && typeof v === "number" ? `${text} ${unit}` : text;
}

/**
 * ux (rollback review #1): "<Entity> · <field> is <live> now, not <base> as <leftBy> left it
 * (changed in r9 by Mira K.). Roll back r9 first, or change it by hand."
 */
export function conflictSentences(item: PreviewItem, leftBy?: string): string | null {
  if (!item.paths || item.paths.length === 0) return null;
  const who = item.entity_name ?? item.entity_id ?? configKindText(item.kind);
  return item.paths
    .map((p) => {
      const since =
        p.changed_in === "outside"
          ? "changed outside a change set"
          : `changed in r${p.changed_in}${p.changed_by?.name ? ` by ${p.changed_by.name}` : ""}`;
      const head = `${who} · ${p.label ?? p.path} is ${valueText(p.live, p.unit, p.format)} now, not ${valueText(p.base, p.unit, p.format)} as ${leftBy ?? "it was when staged"}${leftBy ? " left it" : ""} (${since}).`;
      return p.changed_in === "outside"
        ? `${head} Change it by hand.`
        : `${head} Roll back r${p.changed_in} first, or change it by hand.`;
    })
    .join(" ");
}

const shown = (v: unknown) => (typeof v === "string" ? v : JSON.stringify(v));

/** One line per check item: server sentence first, then both values for a framing mismatch. */
/** `contacts_in_window` → "Contacts in window" (fallback when the server sends no sentence). */
export function humanize(key: string): string {
  const words = key
    .replace(/[_.:-]+/g, " ")
    .trim()
    .toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** #65 catalog generations: holds that acknowledging can't clear, and what clears them. */
const blockingNext: Readonly<Partial<Record<HoldReason, string>>> = {
  catalog_command_in_flight: "Apply when those commands finish.",
  catalog_configuration_pending: "Activate or discard the pending configuration first.",
};

/** A blocking item's "can't apply yet" line: #65 catalog holds by reason, L17/L22 by `blocking`. */
function blockingLine(item: PreviewItem): string | null {
  const said = item.sentence ?? humanize(item.reason ? reasonText(item.reason) : "");
  const next = item.reason && isKnown(item.reason) ? blockingNext[item.reason] : undefined;
  if (next) return `Can't apply yet: ${said} ${next}`;
  return item.blocking === true ? `Can't apply yet: ${said}` : null;
}

/** The first blocking item's "can't apply yet" line, or null when nothing blocks. */
export function blockingReason(preview: Preview): string | null {
  for (const check of preview.checks)
    for (const item of check.items) {
      const line = blockingLine(item);
      if (line) return line;
    }
  return null;
}

export function itemLine(item: PreviewItem, leftBy?: string): string {
  const blocked = blockingLine(item);
  if (blocked) return blocked;
  const conflict = conflictSentences(item, leftBy);
  if (conflict) return conflict;
  // A plain sentence with its raw detail split off reads on its own (ux rollback review #7).
  if (item.sentence && item.detail) return item.sentence;
  if (item.profile_value && item.transport_value) {
    const both = `profile ${item.profile_value.path} = ${shown(item.profile_value.value)} vs ${item.transport_value.transport.name} ${item.transport_value.path} = ${shown(item.transport_value.value)}`;
    const count = item.spacecraft_count == null ? "" : ` · ${item.spacecraft_count} spacecraft`;
    return `${item.sentence ? `${item.sentence} ` : ""}(${both}${count})`;
  }
  // framing_unverified (DECISIONS #40): only the profile side is known.
  if (item.profile_value && item.reason === "framing_unverified") {
    const head = item.sentence ?? "Can't verify against any transport.";
    const count = item.spacecraft_count == null ? "" : ` · ${item.spacecraft_count} spacecraft`;
    return `${head} (profile ${item.profile_value.path} = ${shown(item.profile_value.value)}${count})`;
  }
  if (item.sentence) return item.sentence;
  if (item.errors && item.errors.length > 0)
    return item.errors.map((e) => `${e.path}: ${e.message}`).join("; ");
  return item.reason ? humanize(reasonText(item.reason)) : configKindText(item.kind);
}

/** "Santiago (Demo) S-band downlink" → "Santiago": the station part names a transport in a list. */
function shortTransport(name: string): string {
  const cut = name.search(/ \(| S-band| X-band| Ka-band/);
  return cut > 0 ? name.slice(0, cut) : name;
}

/**
 * Check rows' lines, with framing mismatches that differ only by transport folded into one line:
 * "… would decode 900-byte frames, but 2 transports send 1,115-byte frames (Santiago, Svalbard)."
 */
export function groupedLines(items: readonly PreviewItem[], leftBy?: string): readonly string[] {
  const groups = new Map<string, PreviewItem[]>();
  const order: string[] = [];
  items.forEach((item, i) => {
    const key =
      item.reason === "framing_mismatch" && item.profile_value && item.transport_value
        ? JSON.stringify([
            item.entity_id,
            item.profile_value.path,
            item.profile_value.value,
            item.transport_value.path,
            item.transport_value.value,
          ])
        : `#${i}`;
    if (!groups.has(key)) order.push(key);
    groups.set(key, [...(groups.get(key) ?? []), item]);
  });
  return order.map((key) => {
    const group = groups.get(key) ?? [];
    const first = group[0];
    if (!first) return "";
    if (group.length === 1) return itemLine(first, leftBy);
    const names = group.flatMap((g) =>
      g.transport_value ? [g.transport_value.transport.name] : [],
    );
    const one = first.transport_value?.transport.name ?? "";
    const sentence = first.sentence ?? "";
    const folded = sentence.replace(`but ${one} sends`, `but ${group.length} transports send`);
    return folded !== sentence
      ? `${folded.replace(/\.$/, "")} (${names.map(shortTransport).join(", ")}).`
      : group.map((g) => itemLine(g, leftBy)).join(" · ");
  });
}
