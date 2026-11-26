import { decoders, type Decoded } from "@/api";
import { formatCount, plural } from "@/ui";

/**
 * ux U48 (domain's template-version fix): the template's days an edit leaves alone, from the
 * template supersedes dry run. Kept = planned or started; done = closed or canceled by an operator.
 */
const { array, integer, nullable, object, string } = decoders;
/**
 * One group's exact counts from the server (#793, api #845): distinct UTC days, requirements, and
 * the first and last day. `dates` lists the days only when there are 3 or fewer.
 */
const group = object({
  days: integer,
  requirements: integer,
  dates: array(string, 3),
  first_date: nullable(string),
  last_date: nullable(string),
});
export const decidedReader = object({
  planned_or_started: group,
  closed: group,
  canceled: group,
});
export type Decided = Decoded<typeof decidedReader>;
type DecidedGroup = Decided["closed"];

/** "2026-11-14" → "11-14" (ux §4). */
const md = (date: string) => date.slice(5);

/**
 * One group's sentence, without the full stop; null when the group is empty. Up to 3 days are listed
 * after a colon; above that the span follows the noun (ux: at the end it reads as a window).
 */
function clause(
  group: DecidedGroup,
  adjective: string,
  verb: (one: boolean, byRequirement: boolean, spanned: boolean) => string,
): string | null {
  const { days: n, requirements, dates } = group;
  if (n === 0) return null;
  const spanned = n > 3;
  const byRequirement = requirements !== n;
  const noun = byRequirement
    ? `${formatCount(requirements)} ${adjective}requirements on ${plural(n, "day")}`
    : plural(n, `${adjective}day`, `${adjective}days`);
  const span = spanned
    ? ` between ${md(group.first_date ?? "")} and ${md(group.last_date ?? "")}`
    : "";
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
