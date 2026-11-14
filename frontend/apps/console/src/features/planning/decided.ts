import { decoders, type Decoded } from "@/api";
import { formatCount, plural } from "@/ui";

/**
 * ux U48 (domain's template-version fix): the template's days an edit leaves alone, from the
 * template supersedes dry run. Kept = planned or started; done = closed or canceled by an operator.
 */
const { array, object, string, timestamp, token } = decoders;
const day = object({ occurrence_at: timestamp, date: string, spacecraft_ids: array(token, 5000) });
export const decidedReader = object({
  planned_or_started: array(day, 5000),
  closed: array(day, 5000),
  canceled: array(day, 5000),
});
export type Decided = Decoded<typeof decidedReader>;
type DecidedDay = Decided["closed"][number];

/** "2026-11-14" → "11-14" (ux §4). */
const md = (date: string) => date.slice(5);

/** A group's distinct days (sorted) and its requirement count (U48: the sum of spacecraft ids). */
function tally(days: readonly DecidedDay[]) {
  const dates = [...new Set(days.map((d) => d.date))].sort();
  const requirements = days.reduce((n, d) => n + d.spacecraft_ids.length, 0);
  return { dates, requirements };
}

/**
 * One group's sentence, without the full stop; null when the group is empty. Up to 3 days are listed
 * after a colon; above that the span follows the noun (ux: at the end it reads as a window).
 */
function clause(
  days: readonly DecidedDay[],
  adjective: string,
  verb: (one: boolean, byRequirement: boolean, spanned: boolean) => string,
): string | null {
  const { dates, requirements } = tally(days);
  const n = dates.length;
  if (n === 0) return null;
  const spanned = n > 3;
  const byRequirement = requirements !== n;
  const noun = byRequirement
    ? `${formatCount(requirements)} ${adjective}requirements on ${plural(n, "day")}`
    : plural(n, `${adjective}day`, `${adjective}days`);
  const span = spanned ? ` between ${md(dates[0] ?? "")} and ${md(dates.at(-1) ?? "")}` : "";
  const list = spanned ? "" : `: ${dates.map(md).join(", ")}`;
  return `${noun}${span}${verb(n === 1 && !byRequirement, byRequirement, spanned)}${list}`;
}

/**
 * ux U48's edit-preview count line, one sentence per group: "v3 applies to every day that's still
 * open. 3 days already planned or started keep their requirement: 11-14, 11-15, 11-16. 2 closed days
 * stay closed: 11-12, 11-13." Empty groups drop out; with every group empty the first sentence stands.
 */
export function decidedLine(decided: Decided, nextVersion: number): string {
  const kept = clause(decided.planned_or_started, "", (one, byRequirement, spanned) =>
    byRequirement
      ? ", already planned or started, stay as they are"
      : spanned
        ? ", already planned or started, keep their requirement"
        : one
          ? " already planned or started keeps its requirement"
          : " already planned or started keep their requirement",
  );
  const done = (word: string) => (one: boolean) => (one ? ` stays ${word}` : ` stay ${word}`);
  const closed = clause(decided.closed, "closed ", done("closed"));
  const canceled = clause(decided.canceled, "canceled ", done("canceled"));
  // Every group names its days (a list or "between"), so ux's ", and" pairing becomes a sentence each.
  return [`v${nextVersion} applies to every day that's still open`, kept, closed, canceled]
    .filter((x): x is string => x !== null)
    .map((x) => `${x}.`)
    .join(" ");
}
