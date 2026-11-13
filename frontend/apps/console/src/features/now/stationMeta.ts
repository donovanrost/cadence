import type { StationId } from "@/api/index.ts";
import type { Availability } from "@/features/scheduling/index.ts";

/**
 * Now header meta's last part (Now.md Header, backlog L49): the worst station issue from S7,
 * `SVA DOWN SINCE 01:10Z · 1 MORE STATION ISSUE` or `KIR DEGRADED`; down outranks degraded, then the longest-running.
 * Null when every station is up (nothing is said rather than "all up").
 */
export function worstStationIssue(
  availability: Availability | null,
  codeOf: (stationId: StationId) => string | null,
  now: Date,
): Readonly<{ line: string; all: string[] }> | null {
  const issues = (availability?.stations ?? []).filter((s) => s.state !== "up");
  const rank = (s: (typeof issues)[number]) => (s.state === "down" ? 0 : 1);
  const [worst] = [...issues].sort(
    (a, b) =>
      rank(a) - rank(b) ||
      Date.parse(a.since ?? "9999-12-31T00:00:00Z") - Date.parse(b.since ?? "9999-12-31T00:00:00Z"),
  );
  if (!worst) return null;
  const words = (st: (typeof issues)[number]) => {
    const since = st.since;
    const today = since?.slice(0, 10) === now.toISOString().slice(0, 10);
    const when = since
      ? ` since ${today ? "" : `${since.slice(5, 10)} `}${since.slice(11, 16)}Z`
      : "";
    return `${codeOf(st.ground_station_id) ?? "A station"} ${st.state}${when}`;
  };
  // ux: "· 1 more station issue", not "(+1)"; the hover lists every one.
  const others = issues.length - 1;
  const more = others > 0 ? ` · ${others} more station ${others === 1 ? "issue" : "issues"}` : "";
  return {
    line: `${words(worst)}${more}`,
    all: [worst, ...issues.filter((st) => st !== worst)].map(words),
  };
}
