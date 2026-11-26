import type { MissionId } from "@/api/index.ts";
import type { RouteLocationRaw } from "vue-router";
import { request } from "@/api/index.ts";
import { plural } from "@/ui";
import { attentionReader, serverKey, short, type Attention } from "./attention.ts";
import { passLabel } from "./ingress.ts";
import type { QueueItem } from "./queue.ts";

/**
 * archive_quarantine (ux U49; DECISIONS #88, domain's final shape): raw records from one contact
 * that the archive couldn't take. Their telemetry was still stored, so nothing here says it was
 * lost. Visible text says "archive" and "raw records"; the error, its code and the
 * id stay in Technical details. Retry is synchronous; Discard is resolve with a required reason.
 */

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;

/** "12 frames and 40 packets", dropping a zero count; "raw records" when both are zero. */
export function recordCounts(c: Readonly<{ frames: number; packets: number }> | null | undefined) {
  const parts = [
    c && c.frames > 0 ? plural(c.frames, "frame") : null,
    c && c.packets > 0 ? plural(c.packets, "packet") : null,
  ].filter((p): p is string => p !== null);
  return parts.length ? parts.join(" and ") : "Raw records";
}

/** The pass label (U47's), or null with neither a station nor a pass to name. */
function where(a: Attention, now: Date): string | null {
  return passLabel(a, now);
}

/** `EARENDIL-008 · SVB 03:10Z pass · 12 frames and 40 packets couldn't be archived`. */
export function archiveTitle(a: Attention, spacecraft: string | null, now: Date = new Date()) {
  const what = `${recordCounts(a.counts)} couldn't be archived`;
  return [spacecraft, where(a, now), what].filter(Boolean).join(" · ");
}

const CAUSES = {
  identity_conflict:
    "The archive already holds different records with the same identity, so these weren't added.",
  data_rejected: "The archive rejected their data, so these weren't added.",
} as const;
const cause = (a: Attention) =>
  a.error_code === "identity_conflict" || a.error_code === "data_rejected"
    ? CAUSES[a.error_code]
    : "The archive couldn't take them.";

function stored(a: Attention): string | null {
  const s = a.stored_without_archive;
  if (!s) return null;
  return s.frames === 0 && s.packets === 0
    ? "None of their telemetry was stored."
    : `Their telemetry was still stored: ${recordCounts(s)}, without an archived copy of the raw records.`;
}

/** "Retried by Mira K. at 03:20Z; the rest still couldn't be archived." while some still fail. */
export function retriedLine(a: Attention): string | null {
  const r = a.last_retry;
  if (!r || a.state === "resolved") return null;
  const rest =
    r.indexed === 0 ? "none could be archived yet" : "the rest still couldn't be archived";
  return `Retried by ${r.by.name ?? "an operator"} at ${hhmm(r.at)}; ${rest}.`;
}

/** How a resolved item closed (the row and the Contacts block, until the next read). */
export function archiveClosed(a: Attention): string | null {
  const r = a.resolution;
  if (a.state !== "resolved" || !r) return null;
  if (r.action === "discarded")
    return `Discarded by ${r.actor.name ?? "an operator"} at ${hhmm(r.at)}${r.note ? `: ${r.note.replace(/[.!?]+$/, "")}` : ""}.`;
  if (r.action === "expired")
    return `Expired at ${hhmm(r.at)}: nobody retried or discarded it before its retention ran out, so it was never archived.`;
  return `Archived on retry at ${hhmm(r.at)}.`;
}

export const CHOICE = "Retry once the cause is fixed, or discard them if they can't be archived.";

/** Body: the cause, what was stored, the choice, then the last retry. */
export function archiveEvidence(a: Attention): string {
  const closed = archiveClosed(a);
  if (closed) return closed;
  return [cause(a), stored(a), CHOICE, retriedLine(a)].filter(Boolean).join(" ");
}

const LIVE_WINDOW_MS = 5 * 60_000;
/** U49: more are still arriving while the pass is on and one came in the last 5 min. */
function stillArriving(a: Attention, now: Date): boolean {
  const t = now.getTime();
  const live =
    (a.starts_at == null || Date.parse(a.starts_at) <= t) &&
    (a.ends_at == null || Date.parse(a.ends_at) > t);
  return live && a.last_seen_at != null && t - Date.parse(a.last_seen_at) <= LIVE_WINDOW_MS;
}

/** `12 FRAMES · 40 PACKETS · 03:14Z–03:15Z · STILL ARRIVING`. */
export function archiveMeta(a: Attention, now: Date = new Date()): string | null {
  const c = a.counts;
  const first = a.first_received_at;
  const last = a.last_received_at;
  const one = first ?? last;
  const span =
    first && last && first !== last
      ? `${short(first, now)}–${short(last, now)}`
      : one
        ? short(one, now)
        : null;
  const parts = [
    c && c.frames > 0 ? plural(c.frames, "frame") : null,
    c && c.packets > 0 ? plural(c.packets, "packet") : null,
    span,
    a.state !== "resolved" && stillArriving(a, now) ? "Still arriving" : null,
  ].filter((p): p is string => Boolean(p));
  return parts.length ? parts.join(" · ").toUpperCase() : null;
}

/** Which of Retry / Discard the item offers (the server's list; both when it sends none). */
export const offers = (a: Attention, action: "retry" | "discard") =>
  a.state !== "resolved" && (a.actions == null || a.actions.includes(action));

export const NO_ACCESS_ARCHIVE = "Operators retry or discard records that couldn't be archived.";

/** The Discard sheet's title: `Discard 12 frames and 40 packets that couldn't be archived?`. */
export const discardTitle = (a: Attention) =>
  `Discard ${recordCounts(a.counts).replace(/^Raw/, "the raw")} that couldn't be archived?`;
export const DISCARD_BODY =
  "They won't be archived, and Retry won't be offered for them again. Their stored telemetry stays.";
export const DISCARD_DETAIL = "The raw bytes may still be in the buffer or the ingest archive.";

/** Discard = resolve with the reason as action_text (required, trimmed, ≤ 200; api). */
export function discardArchive(missionId: MissionId, a: Attention, reason: string) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/attention/${encodeURIComponent(serverKey(a.source))}/${encodeURIComponent(a.id)}/resolve`,
    attentionReader,
    { method: "POST", body: { action_text: reason } },
  );
}

export function archiveRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  a: Attention,
  spacecraftName: string | null,
  now: Date = new Date(),
): QueueItem {
  const pass = a.reservation_id ?? a.contact_id;
  const to: RouteLocationRaw = pass
    ? { name: "ops.contacts", query: { contact: pass } }
    : { name: "ops.contacts" };
  const closed = a.state === "resolved";
  return {
    ...base,
    ...(closed ? { state: "off" as const } : {}),
    key,
    title: archiveTitle(a, spacecraftName, now),
    titleTo: to,
    sentence: archiveEvidence(a),
    meta: archiveMeta(a, now),
    action: { label: "Open pass", to },
    ...(offers(a, "retry")
      ? { command: { label: "Retry", kind: "retry" as const, targets: [a] } }
      : {}),
    ...(offers(a, "discard") ? { discard: a } : {}),
  };
}
