import type { RouteLocationRaw } from "vue-router";
import { decoders as d, scid as scidReader, spacecraftRef } from "@/api/index.ts";
import { formatCount } from "@/ui";
import type { Attention } from "./attention.ts";
import { short } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * contact_scid_mismatch (ux U81 §2, api 11-16, DECISIONS #102): a settled contact where most of
 * its frames carried another SCID and were refused. One item per contact, P2 caution, nothing due.
 * Mark as seen resolves it; unseen, it retires 7 days after settle. Its own fields, spread into
 * the attention reader, all optional.
 */
export const scidMismatchFields = {
  /** The pass's craft; a null name is never replaced by its id. */
  spacecraft: d.optional(d.nullable(spacecraftRef)),
  scid_mismatch: d.optional(
    d.nullable(
      d.object({
        expected_scid: scidReader,
        frames: d.integer,
        frames_total: d.integer,
        /** The observed SCIDs over all paths, sorted, at most 8. */
        scids: d.array(scidReader, 64),
        /** A lower bound unless it equals the list's length below 8. */
        scid_count: d.integer,
      }),
    ),
  ),
} as const;

/**
 * "SCID 3" / "SCIDs 3 and 7" / "SCIDs 3, 7 and 9"; more than 3: "12 different SCIDs"; a count
 * that may be short: "at least 12 different SCIDs" (U81 §2; the record line uses it too).
 */
export function scidWords(scids: readonly number[], count: number, atLeast: boolean): string {
  if (atLeast) return `at least ${formatCount(count)} different SCIDs`;
  if (count !== scids.length || count > 3 || !scids.length)
    return `${formatCount(count)} different SCIDs`;
  if (scids.length === 1) return `SCID ${scids[0]}`;
  return `SCIDs ${scids.slice(0, -1).join(", ")} and ${scids.at(-1)}`;
}

/** 'EARENDIL-312 · Most frames on the FBK 03:10Z pass carried another SCID'. */
export function scidMismatchTitle(a: Attention, spacecraft: string | null, now: Date): string {
  const station = a.station?.code ?? a.station?.name ?? null;
  const pass = [station, a.starts_at ? short(a.starts_at, now) : null].filter(Boolean).join(" ");
  const head = spacecraft ? `${spacecraft} · ` : "";
  return `${head}Most frames on the ${pass ? `${pass} ` : ""}pass carried another SCID`;
}

/** '412 of 430 frames carried SCID 3, not EARENDIL-312's SCID 1. Cadence kept them…'. */
export function scidMismatchEvidence(a: Attention, spacecraft: string | null): string {
  const m = a.scid_mismatch;
  if (!m) return "Cadence kept those frames as raw evidence and made no telemetry from them.";
  const n = Math.max(m.scid_count, m.scids.length);
  const complete = n === m.scids.length && n < 8;
  const whose = spacecraft ? `${spacecraft}'s` : "this pass's";
  const them = m.frames === 1 ? "it" : "them";
  const total = m.frames_total === 1 ? "1 frame" : `${formatCount(m.frames_total)} frames`;
  return (
    `${formatCount(m.frames)} of ${total} carried ${scidWords(m.scids, n, !complete)}, ` +
    `not ${whose} SCID ${m.expected_scid}. Cadence kept ${them} as raw evidence and made no ` +
    `telemetry from ${them}.`
  );
}

/** 'FBK 03:10Z · SETTLED 04:12Z': the pass and when it settled, never a countdown. */
export function scidMismatchMeta(a: Attention, now: Date): string {
  const station = a.station?.code ?? a.station?.name ?? null;
  const pass = [station, a.starts_at ? short(a.starts_at, now) : null].filter(Boolean).join(" ");
  return [pass, `Settled ${short(a.raised_at, now)}`].filter(Boolean).join(" · ").toUpperCase();
}

/** The Now row: Open contact record goes to History (U78); Mark as seen resolves it. */
export function scidMismatchRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  a: Attention,
  rowSpacecraft: string | null,
  now: Date = new Date(),
): QueueItem {
  const spacecraft = a.spacecraft?.name ?? rowSpacecraft;
  // api: the scheduled contact, else the realized one (a hand-started contact); History takes either.
  const contact = a.contact_id ?? a.realized_contact_id ?? null;
  const to: RouteLocationRaw = contact
    ? { name: "ops.contacts.history", query: { contact } }
    : { name: "ops.contacts.history" };
  return {
    ...base,
    key,
    title: scidMismatchTitle(a, spacecraft, now),
    titleTo: to,
    sentence: scidMismatchEvidence(a, spacecraft),
    meta: scidMismatchMeta(a, now),
    action: { label: "Open contact record", to },
    ...(a.state === "open"
      ? { command: { label: "Mark as seen", kind: "seen" as const, targets: [a] } }
      : {}),
  };
}
