import type { RouteLocationRaw } from "vue-router";
import { plural } from "@/ui";
import { serverKey, settlementEvidence, short, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * U37 folding (#71 contact_settlement): two or more open items with the same `failure_kind` (null
 * folds with null) become one row, "Telemetry from 37 passes isn't stored yet.", whose action
 * opens every pass in a sheet (the U30 pattern). One item stays its own row.
 */
export const FOLD_AT = 2;

export type Settlement = Readonly<{
  itemId: string;
  spacecraft: Readonly<{ id: string; name: string }> | null;
  /** A settlement is about a pass: it always has a backlog and an AOS. */
  attention: Attention & { backlog: NonNullable<Attention["backlog"]>; starts_at: string };
}>;

/** ux 294e67c6: cause + retry, so manual items never hide inside an automatic fold. */
export const foldKey = (s: Settlement) =>
  s.attention.backlog.lost
    ? "lost"
    : `${s.attention.failure_kind ? serverKey(s.attention.failure_kind) : "none"}:${s.attention.retry === "manual" ? "manual" : "automatic"}`;

const drawer = (a: Attention): RouteLocationRaw => {
  const pass = a.reservation_id ?? a.contact_id;
  return pass ? { name: "ops.contacts", query: { contact: pass } } : { name: "ops.contacts" };
};

/** `11-11 06:01Z … 18:49Z`: the second drops a date the first already gave. */
function span(first: string, last: string, now: Date): string {
  if (first === last) return short(first, now);
  const tail =
    first.slice(0, 10) === last.slice(0, 10) ? `${last.slice(11, 16)}Z` : short(last, now);
  return `${short(first, now)} … ${tail}`;
}

/** One folded row for ≥ FOLD_AT settlements that share a failure_kind. */
export function foldedSettlementRow(
  members: readonly Settlement[],
  now: Date = new Date(),
): QueueItem {
  const sorted = [...members].sort(
    (a, b) => Date.parse(a.attention.starts_at) - Date.parse(b.attention.starts_at),
  );
  const first = sorted[0]?.attention;
  const last = sorted[sorted.length - 1]?.attention;
  const total = sorted.reduce(
    (acc, m) => ({
      entries: acc.entries + m.attention.backlog.entries,
      bytes: acc.bytes + m.attention.backlog.bytes,
    }),
    { entries: 0, bytes: 0 },
  );
  const messages = new Set(sorted.map((m) => m.attention.failure_message ?? null));
  const message = messages.size === 1 ? (first?.failure_message ?? null) : null;
  const n = sorted.length;
  const lost = first?.backlog.lost === true;
  const manual = !lost && first?.retry === "manual";
  const queued = sorted.reduce((acc, m) => acc + (m.attention.backlog.queued ?? 0), 0);
  return {
    key: `settlement:${sorted[0] ? foldKey(sorted[0]) : "none"}`,
    priority: 2,
    state: "caution",
    title: lost
      ? `Telemetry from ${plural(n, "pass", "passes")} was lost.`
      : manual
        ? `Cadence stopped retrying for ${plural(n, "pass", "passes")}.`
        : `Telemetry from ${plural(n, "pass", "passes")} isn't stored yet.`,
    titleTo: null,
    // Folded: summed backlog, no deadline time (ux 3f61ef71), no per-item try times.
    sentence: lost
      ? `${queued.toLocaleString("en-US")} ${queued === 1 ? "batch wasn't" : "batches weren't"} stored and can't be recovered.`
      : settlementEvidence(
          {
            lost: false,
            queued: null,
            backlog: total,
            failureKind: first?.failure_kind ?? null,
            failureMessage: message,
            deadline: null,
            retry: first?.retry ?? null,
            attempts: null,
            nextAttemptAt: null,
            lastAttemptAt: null,
          },
          now,
        ),
    meta: first && last ? span(first.starts_at, last.starts_at, now).toUpperCase() : null,
    action: { label: `Show all ${n}`, to: { name: "ops.contacts" } },
    ...(manual
      ? {
          command: {
            label: `Retry all ${n}`,
            kind: "retry" as const,
            targets: sorted.map((m) => m.attention),
          },
        }
      : {}),
    spacecraftIds: [...new Set(sorted.flatMap((m) => (m.spacecraft ? [m.spacecraft.id] : [])))],
    memberKeys: sorted.map((m) => m.itemId),
    list: {
      title: `Telemetry from ${plural(n, "pass", "passes")} ${lost ? "was lost" : "isn't stored yet"}`,
      rows: sorted.map((m) => {
        const a = m.attention;
        const station = a.station?.code ?? a.station?.name;
        const one = a.backlog.entries === 1;
        return {
          key: m.itemId,
          text: [m.spacecraft?.name, station, short(a.starts_at, now)].filter(Boolean).join(" · "),
          detail: `${a.backlog.entries.toLocaleString("en-US")} ${one ? "entry" : "entries"}`,
          to: drawer(a),
        };
      }),
    },
  };
}
