import type { RouteLocationRaw } from "vue-router";
import { decoders as d, spacecraftRef, stationRef, type Decoded } from "@/api/index.ts";
import { formatShort } from "@/ui";
import { size } from "./ingress.ts";
import type { QueueItem, SentencePart } from "./queue.ts";

/**
 * ux U66 · the telemetry buffer DISK filling (api-ops' shape, 13d313177): every pass's received
 * telemetry waits on one disk until it's stored, then 72 h for review; when the disk is full every
 * pass is refused at once. One item per mission (ingress_backpressure / journal_disk), no pass of
 * its own. "Buffer disk" in visible text; journal and streams only in Technical details.
 */

const holder = d.object({
  realized_contact_id: d.nullable(d.token),
  contact_id: d.nullable(d.token),
  spacecraft_id: d.nullable(d.token),
  /** api-ops (asked 11-15): the holder's names, so the row needs no extra reads. */
  spacecraft: d.optional(d.nullable(spacecraftRef)),
  station: d.optional(d.nullable(stationRef)),
  // free-text: the provider's own station reference, a fallback label only
  ground_station_ref: d.nullable(d.string),
  starts_at: d.nullable(d.timestamp),
  ends_at: d.nullable(d.timestamp),
  bytes: d.integer,
  state: d.knownText(["storing", "kept"] as const),
  kept_until: d.nullable(d.timestamp),
});

export const journalDiskReader = d.object({
  percent: d.integer,
  used_bytes: d.integer,
  size_bytes: d.integer,
  /** Signed; null until two readings. */
  rate_bytes_per_hour: d.nullable(d.integer),
  /** null unless it's growing. */
  eta_full_s: d.nullable(d.integer),
  holders: d.array(holder, 3),
  more_count: d.integer,
  other_missions_bytes: d.integer,
  refusing: d.boolean,
  refused_since: d.nullable(d.timestamp),
});
export type JournalDisk = Decoded<typeof journalDiskReader>;
type Holder = JournalDisk["holders"][number];

/** Spread into the attention reader (absent on every other item). */
export const journalDiskFields = { journal_disk: d.optional(d.nullable(journalDiskReader)) };

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;

/** "Telemetry buffer disk 72% full" / "…91% full: at 100% all telemetry stops" / full. */
export function diskTitle(j: JournalDisk): string {
  if (j.refusing)
    return "Telemetry buffer disk full: Cadence is refusing telemetry from every pass";
  if (j.percent >= 90)
    return `Telemetry buffer disk ${j.percent}% full: at 100% all telemetry stops`;
  return `Telemetry buffer disk ${j.percent}% full`;
}

/** "~6 H" / "~40 MIN" (the meta is upper case). */
function eta(seconds: number): string {
  if (seconds < 3600) return `~${Math.max(1, Math.round(seconds / 60))} min`;
  return `~${Math.round(seconds / 3600)} h`;
}

/** "31 GB OF 43 GB · +1.8 GB/H · FULL IN ~6 H"; shrinking: "… · −900 MB/H · DRAINING". */
export function diskMeta(j: JournalDisk): string {
  const parts = [`${size(j.used_bytes)} of ${size(j.size_bytes)}`];
  const rate = j.rate_bytes_per_hour;
  if (rate !== null && rate > 0) {
    parts.push(`+${size(rate)}/h`);
    if (j.eta_full_s !== null) parts.push(`full in ${eta(j.eta_full_s)}`);
  } else if (rate !== null && rate < 0) parts.push(`−${size(-rate)}/h`, "draining");
  return parts.join(" · ").toUpperCase();
}

/** "EARENDIL-008 · SVB 03:10Z pass" (U47's pass naming). */
function holderName(h: Holder): string {
  const sc = h.spacecraft?.name ?? null;
  const station = h.station?.code ?? h.station?.name ?? h.ground_station_ref;
  const pass = [station, h.starts_at ? hhmm(h.starts_at) : null].filter(Boolean).join(" ");
  return [sc, pass ? `${pass} pass` : "pass"].filter(Boolean).join(" · ");
}

/** " (800 MB, still being stored)" / " (1.2 GB, kept until 11-16 02:48Z)" (ux: no more colons). */
function holderState(h: Holder): string {
  if (h.state === "storing") return ` (${size(h.bytes)}, still being stored)`;
  const until = h.kept_until ? `, kept until ${formatShort(new Date(h.kept_until))}` : "";
  return ` (${size(h.bytes)}${until})`;
}

const passTo = (h: Holder): RouteLocationRaw =>
  h.contact_id
    ? { name: "ops.contacts", query: { contact: h.contact_id } }
    : { name: "ops.contacts" };

const KEEPS =
  "Cadence keeps each pass's received telemetry on this disk, until it's stored and then for 72 h for review. When the disk is full, Cadence stops accepting telemetry from every pass at once.";
const REFUSED = "Telemetry arriving now is refused and isn't kept. It can't be recovered.";
const FREES =
  "It frees up as passes reach 72 h after they end. A pass still being stored holds its share longer.";
const OPEN_IT = "Operators can open what's holding it.";
const SIZE_SET = "The buffer's size is set where Cadence is deployed.";

/** The body, holders as links (ux U66). Joined plain, it's the row's `sentence` too. */
export function diskParts(j: JournalDisk): SentencePart[] {
  const parts: SentencePart[] = [`${KEEPS} `];
  if (j.refusing) parts.push(`${REFUSED} `);
  if (j.holders.length) {
    parts.push("Holding the most: ");
    j.holders.forEach((h, i) => {
      parts.push({ text: holderName(h), to: passTo(h) }, holderState(h));
      if (i < j.holders.length - 1) parts.push("; ");
    });
    if (j.more_count) parts.push(`; and ${j.more_count} more of this mission's passes`);
    if (j.other_missions_bytes)
      parts.push(`; and ${size(j.other_missions_bytes)} from other missions`);
    parts.push(". ");
  } else if (j.other_missions_bytes) {
    parts.push(`${size(j.other_missions_bytes)} of it is from other missions. `);
  }
  // With none of this mission's passes to open, there's nothing for an operator to open (ux).
  parts.push(j.holders.length ? `${FREES} ${OPEN_IT} ${SIZE_SET}` : `${FREES} ${SIZE_SET}`);
  return parts;
}

const plain = (parts: readonly SentencePart[]) =>
  parts.map((p) => (typeof p === "string" ? p : p.text)).join("");

export function diskRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  j: JournalDisk,
): QueueItem {
  const parts = diskParts(j);
  const largest = j.holders[0];
  return {
    ...base,
    key,
    state: j.refusing || j.percent >= 90 ? "crit" : "caution",
    title: diskTitle(j),
    titleTo: null,
    sentence: plain(parts),
    sentenceParts: parts,
    meta: diskMeta(j),
    // Open pass is the only action (no cap control, ux/lead): the largest holder of this mission.
    ...(largest
      ? { action: { label: "Open pass", to: passTo(largest) } }
      : { action: { label: "", to: { name: "ops.contacts" } }, noAction: true }),
  };
}

/** Resolved: "Back under 60% at 03:30Z." (+ "Telemetry was refused from 03:21Z to 03:24Z."). */
export function diskResolvedWords(
  at: string,
  refused: Readonly<{ from: string; to: string }> | null | undefined,
): string {
  const back = `Back under 60% at ${at}.`;
  return refused
    ? `${back} Telemetry was refused from ${hhmm(refused.from)} to ${hhmm(refused.to)}.`
    : back;
}
