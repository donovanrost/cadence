import type { MissionId } from "@/api/index.ts";
import { request } from "@/api/index.ts";
import { attentionReader, serverKey, type Attention } from "./attention.ts";
import { keepWhole, type QueueItem } from "./queue.ts";
import { bufferLine, stuckMeta, stuckTitle, whatStopped } from "./stuckProcessing.ts";

/**
 * replay_conflict's Now row and sheet plumbing (ux U84 layout, 11-17): the row says what's stuck
 * (the dropping line while dropping); ACK in the meta carries the ack. `Acknowledge…` (operators,
 * while open) or `Details` opens the same sheet.
 */

export const NO_ACCESS_STUCK = "Operators acknowledge this.";
/** api: 422 invalid_note (over 500 characters, or not text). */
export const NOTE_MAX = 500;

type Base = Pick<QueueItem, "priority" | "spacecraftIds">;

/** The craft names a line may hold, kept whole when it wraps (ux U84). */
export const craftNames = (a: Attention): string[] =>
  (a.affected_spacecraft ?? []).flatMap((c) => (c.name ? [c.name] : []));

export function stuckRow(b: Base, key: string, a: Attention, now: Date = new Date()): QueueItem {
  const sentence = (a.dropping ? bufferLine(a, now) : null) ?? whatStopped(a);
  return {
    ...b,
    key,
    // U84: crit ◆ only while new telemetry is being lost; otherwise caution ▲.
    state: a.dropping ? "crit" : "caution",
    title: stuckTitle(a, now),
    titleTo: null,
    sentence,
    sentenceParts: keepWhole(sentence, craftNames(a)),
    meta: stuckMeta(a, now),
    acknowledged: a.state === "acknowledged" && !a.reraised,
    // The sheet takes the action slot; this route is never shown.
    action: { label: "Details", to: { name: "ops.now" } },
    stuck: a,
  };
}

/** Open, or open again after an ack because dropping started (U84 re-raise). */
export const stuckOpen = (a: Attention) => a.state === "open";

/** The row's action: `Acknowledge…` for operators while open, else `Details`; primary when dropping. */
export function stuckAction(a: Attention, canAck: boolean) {
  const ack = canAck && stuckOpen(a);
  return { label: ack ? "Acknowledge…" : "Details", primary: ack && a.dropping === true };
}

/**
 * U84 cause tag: an item whose own cause is the stuck processing reads `STUCK PROCESSING` first in
 * its meta and offers no Retry storing at all (ux 11-17: its evidence already says why); its
 * route action (Review) stays.
 */
export function tagStuck(row: QueueItem, causes: readonly Attention[]): QueueItem {
  if (!causes.some((a) => a.stuck_processing_id)) return row;
  const { command, ...rest } = row;
  return {
    ...rest,
    meta: ["STUCK PROCESSING", row.meta].filter(Boolean).join(" · "),
    ...(command && command.kind !== "retry" ? { command } : {}),
  };
}

/**
 * Technical details, and Copy details' plain text (U84: source, path, unit, spacecraft, pass,
 * since, last seen, occurrences, buffer, error). Ids and internal words belong here.
 */
export function stuckTechnical(a: Attention): string[] {
  const craft = (a.affected_spacecraft ?? []).map((c) => (c.name ? `${c.name} (${c.id})` : c.id));
  const count = a.spacecraft_count ?? craft.length;
  const buffer = a.buffer
    ? `${a.buffer.used_bytes} of ${a.buffer.max_bytes} bytes${a.dropping ? `, full since ${a.dropping_since ?? "unknown"}` : ""}`
    : null;
  const lines: [string, string | number | null | undefined][] = [
    [
      "Source",
      `Stuck processing (${serverKey(a.source)}${a.conflict ? `, ${serverKey(a.conflict)}` : ""})`,
    ],
    ["Item", a.id],
    ["Path", a.path ? serverKey(a.path) : null],
    ["Partition", a.partition_id],
    ["Partition stopped", a.partition_stopped ? "yes" : null],
    ["Stream", a.stream_key],
    ["Path id", a.path_id],
    [
      "Spacecraft",
      craft.length ? `${craft.join(", ")}${count > craft.length ? ` (${count} known)` : ""}` : null,
    ],
    ["Pass", a.contact?.id],
    ["Realized contact", a.realized_contact_id],
    ["Since", a.first_seen_at],
    ["Last seen", a.last_seen_at],
    ["Occurrences", a.occurrences],
    ["Buffer", buffer],
    [
      "Error",
      a.effect_kind ? `${serverKey(a.effect_kind)} ${a.effect_id ?? ""}`.trim() : a.effect_id,
    ],
    ["Effects", a.effect_count],
  ];
  return lines.flatMap(([k, v]) =>
    v === null || v === undefined || v === "" ? [] : [`${k}: ${v}`],
  );
}

/** POST …/attention/replay_conflict/:id/acknowledge with the optional note; answers the item. */
export function acknowledgeStuck(missionId: MissionId, a: Attention, note: string) {
  const text = note.trim();
  return request(
    `/missions/${encodeURIComponent(missionId)}/attention/${encodeURIComponent(serverKey(a.source))}/${encodeURIComponent(a.id)}/acknowledge`,
    attentionReader,
    { method: "POST", body: text ? { note: text } : {} },
  );
}
