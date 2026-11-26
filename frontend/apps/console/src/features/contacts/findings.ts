import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import {
  decoders as d,
  spacecraftRef,
  stationRef,
  isKnown,
  knownText,
  requestPage,
  useRemoteQuery,
  type ApiResult,
  type Decoded,
} from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";

/**
 * M22 contact findings for D4 "Needs a decision" (contacts.md §contact-findings): double
 * bookings, bookings into an outage, and coverage gaps over the Contacts window. `message` is the
 * server's sentence; `fix` is null for now, so each row offers `Open in Plan`.
 */
/** M22 finding kinds the console titles (contacts.md §contact-findings). */
export const findingKinds = [
  "station_double_booked",
  "booked_into_outage",
  "coverage_gap",
] as const;
type FindingKind = (typeof findingKinds)[number];

/** §12 A5: the shared station reference. */
const station = d.nullable(stationRef);
const finding = d.object({
  id: d.string,
  kind: knownText(findingKinds),
  severity: d.oneOf(["caution", "critical"] as const),
  at: d.nullable(d.timestamp),
  station,
  message: d.string,
  passes: d.array(d.object({ id: d.token, starts_at: d.timestamp }), 100),
  /** Coverage gaps name the spacecraft and the gap; D4 folds same-cause gaps by them (ux §7). */
  spacecraft: d.optional(d.nullable(spacecraftRef)),
  gap: d.optional(d.nullable(d.object({ from: d.timestamp, to: d.timestamp, seconds: d.integer }))),
});
/** The most findings one page carries (api #845: limit up to 500). */
const FINDINGS_PAGE_LIMIT = 500;
/** One page; `counts` are the whole window's on every page (#793, api #845). */
const findingsPageReader = d.object({
  counts: d.object({ conflicts: d.integer, gaps: d.integer }),
  findings: d.array(finding, FINDINGS_PAGE_LIMIT),
});
export type Findings = Decoded<typeof findingsPageReader>;
export type Finding = Findings["findings"][number];

/**
 * Every finding in the window (#793): pages walked to the server's last cursor with the same
 * window, so D4 folds same-cause gaps over all of them. A failed page fails the read.
 */
export async function fetchFindings(
  missionId: MissionId,
  window: Readonly<{ from: Date; to: Date }>,
  signal?: AbortSignal,
): Promise<ApiResult<Findings>> {
  const q = new URLSearchParams({
    from: window.from.toISOString(),
    to: window.to.toISOString(),
    limit: String(FINDINGS_PAGE_LIMIT),
  });
  const path = `/missions/${encodeURIComponent(missionId)}/contact-findings`;
  const options = signal ? { signal } : {};
  const page = (cursor: string | null) => {
    if (cursor !== null) q.set("cursor", cursor);
    return requestPage(`${path}?${q.toString()}`, findingsPageReader, options);
  };
  const first = await page(null);
  if (!first.ok) return first;
  const findings = [...first.value.value.findings];
  let cursor = first.value.nextCursor;
  while (cursor !== null) {
    const next = await page(cursor);
    if (!next.ok) return next;
    findings.push(...next.value.value.findings);
    cursor = next.value.nextCursor;
  }
  return { ok: true, value: { counts: first.value.value.counts, findings } };
}

/** Findings over now → now + span; refetched on contacts and stations. */
export function useFindings(missionId: Ref<MissionId>, spanMs: Ref<number>) {
  // A typed key (§12 A4; useRemoteQuery compares by value), so the MissionId stays one.
  const key = computed(() => ({ m: missionId.value, ms: spanMs.value }));
  const query = useRemoteQuery(key, (k, signal) => {
    const now = Date.now();
    return fetchFindings(k.m, { from: new Date(now), to: new Date(now + k.ms) }, signal);
  });
  useMissionInvalidation(missionId, ["contacts", "stations"], query.refetch);
  return query;
}

const TITLE: Readonly<Record<FindingKind, string>> = {
  station_double_booked: "double-booked",
  booked_into_outage: "booked into an outage",
  coverage_gap: "coverage gap",
};
const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;

/** Row title: "SVB double-booked 03:20Z", "Coverage gap"; mono ids stay in the message. */
export function findingTitle(f: Finding): string {
  // A kind this console doesn't know reads from its own key (typing §12: knownText keeps it).
  const what = isKnown(f.kind) ? TITLE[f.kind] : f.kind.unrecognized.replaceAll("_", " ");
  const where = f.station?.code ?? f.station?.name ?? null;
  const when = f.at ? ` ${hhmm(f.at)}` : "";
  const text = where ? `${where} ${what}${when}` : `${what}${when}`;
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/** Header meta pieces: "2 conflicts · 1 coverage gap" (only what's non-zero). */
export function findingsMeta(f: Findings | null): string | null {
  if (!f) return null;
  const parts = [
    f.counts.conflicts
      ? `${f.counts.conflicts} ${f.counts.conflicts === 1 ? "conflict" : "conflicts"}`
      : null,
    f.counts.gaps ? `${f.counts.gaps} coverage ${f.counts.gaps === 1 ? "gap" : "gaps"}` : null,
  ].filter((p): p is string => p !== null);
  return parts.length ? parts.join(" · ") : null;
}
