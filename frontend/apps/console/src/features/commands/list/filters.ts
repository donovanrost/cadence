import type { LocationQuery } from "vue-router";
import { plural } from "@/ui";

/**
 * ux U69 A5a + U72 A5b: the Commands filter row, all in the URL (?q=, ?target=, ?stage=), applied
 * by the server (api ccddc894b). While any is set the tabs give way to one result line.
 */
export const STAGES = [
  "release_failed",
  "verify_failed",
  "indeterminate",
  "in_flight",
  "queued_for_contact",
] as const;
export type Stage = (typeof STAGES)[number];
/** The stage words (ux U69 A5a). */
export const STAGE_FILTER_WORDS: Readonly<Record<Stage, string>> = {
  release_failed: "Release failed",
  verify_failed: "Verify failed",
  indeterminate: "Outcome unclear",
  in_flight: "Sending or verifying",
  queued_for_contact: "Queued for AOS",
};
export const Q_MAX = 100;

export type CommandFilters = Readonly<{ q: string; target: string | null; stages: Stage[] }>;

const isStage = (s: string): s is Stage => (STAGES as readonly string[]).includes(s);

export function filtersOf(query: LocationQuery): CommandFilters {
  const raw = typeof query.stage === "string" ? query.stage.split(",") : [];
  return {
    q: typeof query.q === "string" ? query.q.trim() : "",
    target: typeof query.target === "string" && query.target ? query.target : null,
    stages: STAGES.filter((s) => raw.filter(isStage).includes(s)),
  };
}

export const filtered = (f: CommandFilters) =>
  f.q !== "" || f.target !== null || f.stages.length > 0;

/** ux U72: over 100 characters the search isn't sent. */
export const qProblem = (q: string) =>
  q.length > Q_MAX ? "Keep the search under 100 characters." : null;

/** The query with one filter changed; empty values leave the URL. */
export function withFilter(
  query: LocationQuery,
  key: "q" | "target" | "stage",
  value: string | null,
): LocationQuery {
  const { [key]: _drop, ...rest } = query;
  return value ? { ...rest, [key]: value } : rest;
}

/** The parts the line and the empty state name: 'Failed, Outcome unclear', '“heater”', 'on X'. */
function parts(f: CommandFilters, nameOf: (id: string) => string) {
  return {
    stages: f.stages.map((s) => STAGE_FILTER_WORDS[s]).join(", "),
    q: f.q ? `“${f.q}”` : "",
    target: f.target ? nameOf(f.target) : "",
  };
}

/**
 * ux U72: the result line claims only what's known: with more pages '12 shown · Failed · matching
 * “heater” · on EARENDIL-312'; once everything's loaded '12 commands · …'.
 */
export function resultLine(
  f: CommandFilters,
  shown: number,
  more: boolean,
  nameOf: (id: string) => string,
): string {
  const p = parts(f, nameOf);
  const head = more ? `${shown} shown` : plural(shown, "command");
  return [head, p.stages, p.q && `matching ${p.q}`, p.target && `on ${p.target}`]
    .filter(Boolean)
    .join(" · ");
}

/** ux U72: 'No commands match: Failed · “heater”.' (with the target when set). */
export function emptyLine(f: CommandFilters, nameOf: (id: string) => string): string {
  const p = parts(f, nameOf);
  const said = [p.stages, p.q, p.target && `on ${p.target}`].filter(Boolean).join(" · ");
  return `No commands match: ${said}.`;
}
