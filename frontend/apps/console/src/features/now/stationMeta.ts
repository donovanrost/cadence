import type { Availability } from "@/features/scheduling/index.ts";

/**
 * Now header meta's last part (Now.md Header, backlog L49): the worst station issue from S7,
 * `SVA DOWN SINCE 01:10Z` or `KIR DEGRADED`; down outranks degraded, then the longest-running.
 * Null when every station is up (nothing is said rather than "all up").
 */
export function worstStationIssue(
  availability: Availability | null,
  codeOf: (stationId: string) => string | null,
  now: Date,
): string | null {
  const issues = (availability?.stations ?? []).filter((s) => s.state !== "up");
  const rank = (s: (typeof issues)[number]) => (s.state === "down" ? 0 : 1);
  const [worst] = [...issues].sort(
    (a, b) =>
      rank(a) - rank(b) ||
      Date.parse(a.since ?? "9999-12-31T00:00:00Z") - Date.parse(b.since ?? "9999-12-31T00:00:00Z"),
  );
  if (!worst) return null;
  const name = codeOf(worst.ground_station_id) ?? "A station";
  const since = worst.since;
  const today = since?.slice(0, 10) === now.toISOString().slice(0, 10);
  const when = since
    ? ` since ${today ? "" : `${since.slice(5, 10)} `}${since.slice(11, 16)}Z`
    : "";
  const more = issues.length > 1 ? ` (+${issues.length - 1})` : "";
  return `${name} ${worst.state}${when}${more}`;
}
