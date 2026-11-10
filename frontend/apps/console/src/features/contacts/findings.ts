import { computed, type Ref } from "vue";
import {
  decoders as d,
  request,
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
const station = d.nullable(
  d.object({
    ref: d.nullable(d.string),
    id: d.nullable(d.token),
    code: d.nullable(d.string),
    name: d.nullable(d.string),
  }),
);
const finding = d.object({
  id: d.string,
  kind: d.token,
  severity: d.oneOf(["caution", "critical"] as const),
  at: d.nullable(d.timestamp),
  station,
  message: d.string,
  passes: d.array(d.object({ id: d.token, starts_at: d.timestamp }), 100),
});
const findingsReader = d.object({
  truncated: d.boolean,
  counts: d.object({ conflicts: d.integer, gaps: d.integer }),
  findings: d.array(finding, 1_000),
});
export type Findings = Decoded<typeof findingsReader>;
export type Finding = Findings["findings"][number];

export function fetchFindings(
  missionId: string,
  window: Readonly<{ from: Date; to: Date }>,
  signal?: AbortSignal,
): Promise<ApiResult<Findings>> {
  const q = new URLSearchParams({ from: window.from.toISOString(), to: window.to.toISOString() });
  return request(
    `/missions/${encodeURIComponent(missionId)}/contact-findings?${q.toString()}`,
    findingsReader,
    signal ? { signal } : {},
  );
}

/** Findings over now → now + span; refetched on contacts and stations. */
export function useFindings(missionId: Ref<string>, spanMs: Ref<number>) {
  const key = computed(() => `${missionId.value}|${spanMs.value}`);
  const query = useRemoteQuery(key, (k, signal) => {
    const [m = "", ms = "0"] = k.split("|");
    const now = Date.now();
    return fetchFindings(m, { from: new Date(now), to: new Date(now + Number(ms)) }, signal);
  });
  useMissionInvalidation(missionId, ["contacts", "stations"], query.refetch);
  return query;
}

const TITLE: Readonly<Record<string, string>> = {
  station_double_booked: "double-booked",
  booked_into_outage: "booked into an outage",
  coverage_gap: "coverage gap",
};
const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;

/** Row title: "SVB double-booked 03:20Z", "Coverage gap"; mono ids stay in the message. */
export function findingTitle(f: Finding): string {
  const what = TITLE[f.kind] ?? f.kind.replaceAll("_", " ");
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
