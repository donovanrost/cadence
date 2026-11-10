import type { ApiResult } from "@/api";
import type { ReviewKey, ReviewRow } from "./api.ts";
import { causeText, outcomeTag, ownerWord, stationText } from "./format.ts";

/**
 * K3 Export CSV (lead; ux af1c78d1 + review): every R4 missed/failed/partial pass for the window,
 * one row per pass (no summary rows, so sums don't double-count), time and volume facts only (no
 * money, DECISIONS #63). Times are full ISO UTC; outcome, cause and owner are words.
 */
const header = [
  "Station",
  "Provider",
  "Spacecraft",
  "Planned AOS (UTC)",
  "Planned LOS (UTC)",
  "Actual AOS (UTC)",
  "Actual LOS (UTC)",
  "Outcome",
  "Cause",
  "Owner",
  "Planned minutes",
  "Flown minutes",
  "Provider-reported bytes",
  "Received bytes",
] as const;

const cell = (v: string | number | null | undefined): string => {
  if (v === null || v === undefined) return "";
  const t = String(v);
  return /[",\n\r]/.test(t) ? `"${t.replaceAll('"', '""')}"` : t;
};
const mins = (s: number | null) => (s === null ? null : Math.round((s / 60) * 10) / 10);
/** "2026-11-10T02:59:40Z": full ISO UTC that spreadsheets parse. */
const iso = (t: string | null) =>
  t === null ? null : new Date(t).toISOString().replace(/\.\d{3}Z$/, "Z");

/** What the CSV reads of a lost pass (ReviewRow fits). */
export type LostLine = Pick<
  ReviewRow,
  | "station"
  | "provider"
  | "spacecraft"
  | "planned_aos"
  | "planned_los"
  | "actual_aos"
  | "actual_los"
  | "outcome"
  | "cause"
  | "owner"
  | "planned_seconds"
  | "flown_seconds"
  | "provider_bytes"
  | "received_bytes"
>;

export function reviewCsv(lost: readonly LostLine[]): string {
  const lines = lost.map((r) => [
    stationText(r.station),
    r.provider?.name ?? null,
    r.spacecraft.name ?? r.spacecraft.id,
    iso(r.planned_aos),
    iso(r.planned_los),
    iso(r.actual_aos),
    iso(r.actual_los),
    outcomeTag(r.outcome).label,
    causeText(r.cause),
    r.owner ? ownerWord[r.owner] : null,
    mins(r.planned_seconds),
    mins(r.flown_seconds),
    r.provider_bytes,
    r.received_bytes,
  ]);
  return [header.join(","), ...lines.map((l) => l.map(cell).join(","))].join("\r\n") + "\r\n";
}

/** `pass-review-earendil-2026-11-09.csv`, or the range for Week/Month (UTC dates, end inclusive). */
export function reviewFileName(
  missionSlug: string,
  key: ReviewKey,
  from: string,
  to: string,
): string {
  if (key.span === "day") return `pass-review-${missionSlug}-${key.day}.csv`;
  const last = new Date(Date.parse(to) - 1).toISOString().slice(0, 10);
  return `pass-review-${missionSlug}-${from.slice(0, 10)}_${last}.csv`;
}

/** Every lost-pass page for the window (cursor walk, capped so a runaway can't loop forever). */
export async function allLost<T>(
  key: ReviewKey,
  fetchPage: (
    k: ReviewKey & { cursor?: string },
  ) => Promise<
    ApiResult<Readonly<{ rows: readonly T[]; next_cursor?: string | null | undefined }>>
  >,
): Promise<ApiResult<T[]>> {
  const rows: T[] = [];
  let cursor: string | undefined;
  for (let page = 0; page < 400; page += 1) {
    const r = await fetchPage(cursor ? { ...key, cursor } : key);
    if (!r.ok) return r;
    rows.push(...r.value.rows);
    if (!r.value.next_cursor) return { ok: true, value: rows };
    cursor = r.value.next_cursor;
  }
  return { ok: true, value: rows };
}
