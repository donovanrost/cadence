import { actorKindWord } from "@/api";
import { plural } from "@/ui";
import type { ApiResult } from "@/api";
import { kindText, type AuditEvent, type AuditPage, type AuditQuery } from "./api.ts";

/**
 * Audit `Export CSV` (SettingsAuditProviders.md): every event for the current filter, one row per
 * event, full ISO UTC times, words for the kind. Built client-side from the audit read's pages.
 */
const header = ["Time (UTC)", "Actor", "Actor kind", "Kind", "Action", "Target", "Mission", "Why"];

/** At most this many events in one file; past it the export says so instead of implying all. */
export const exportCap = 10_000;

const cell = (v: string | null | undefined): string => {
  if (v === null || v === undefined) return "";
  return /[",\n\r]/.test(v) ? `"${v.replaceAll('"', '""')}"` : v;
};

export function auditCsv(events: readonly AuditEvent[]): string {
  const lines = events.map((e) => [
    new Date(e.at).toISOString().replace(/\.\d{3}Z$/, "Z"),
    e.actor?.name ?? null,
    actorKindWord(e.actor?.kind ?? null),
    kindText(e.kind),
    e.action,
    e.target?.label ?? null,
    e.mission?.name ?? null,
    e.reason,
  ]);
  return [header, ...lines].map((l) => l.map(cell).join(",")).join("\r\n") + "\r\n";
}

/** Walks the cursor until the end or the cap; `capped` when events were left out. */
export async function allEvents(
  query: AuditQuery,
  fetchPage: (q: AuditQuery) => Promise<ApiResult<AuditPage>>,
): Promise<ApiResult<{ events: AuditEvent[]; capped: boolean; unshown: number }>> {
  const events: AuditEvent[] = [];
  // U86: events the console couldn't read never reach the file; the note says how many.
  let unshown = 0;
  let cursor: string | undefined;
  for (;;) {
    const r = await fetchPage(cursor ? { ...query, cursor } : query);
    if (!r.ok) return r;
    events.push(...r.value.events);
    unshown += r.value.unshown.length;
    if (events.length >= exportCap)
      return { ok: true, value: { events: events.slice(0, exportCap), capped: true, unshown } };
    if (!r.value.next_cursor) return { ok: true, value: { events, capped: false, unshown } };
    cursor = r.value.next_cursor;
  }
}

/** ux U86: "3 events couldn't be read, so they aren't in this file." */
export const unreadNote = (n: number) =>
  `${plural(n, "event")} couldn't be read, so ${n === 1 ? "it isn't" : "they aren't"} in this file.`;

/** `audit-reflect-orbital-2026-11-06_2026-11-12.csv` (the window's first and last UTC days). */
export function auditFileName(orgSlug: string, query: AuditQuery): string {
  const to = Date.parse(query.to);
  const first = new Date(to - query.days * 86_400_000).toISOString().slice(0, 10);
  const last = new Date(to - 1).toISOString().slice(0, 10);
  return `audit-${orgSlug}-${first}_${last}.csv`;
}
