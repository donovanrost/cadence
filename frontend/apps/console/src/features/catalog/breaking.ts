import { plural } from "@/ui";
import type { ImportRunDetail } from "./importRun.ts";

/**
 * U102 (amended by #363): what C3 knows about a revision's breaking changes. Only the server's
 * fields decide it, never the console, and a count Cadence doesn't know is never 0 (U20: 0 would
 * claim nothing breaks).
 * - `count`: the server's count, against `base` (the revision before it in its database).
 * - `first`: the database's first revision; there's nothing earlier to compare it with.
 * - `uncompared`: the diff against `base` couldn't be read, on either page (#364).
 * - `unknown`: a revision's page on a server without #365's fields; its import's diff may still
 *   say, so it links there when the read names the run.
 */
export type Breaking =
  | Readonly<{ kind: "count"; count: number; base: number }>
  | Readonly<{ kind: "first" }>
  | Readonly<{ kind: "uncompared"; base: number }>
  | Readonly<{ kind: "unknown"; importRunId: string | null }>;

/**
 * The import page's C3, from its run's `base_revision` and `diff` (#364). The server sends a diff
 * only with a base (setup.md C3), so no base is the first revision.
 */
export function importBreaking(run: Pick<ImportRunDetail, "base_revision" | "diff">): Breaking {
  if (run.base_revision === null) return { kind: "first" };
  const base = run.base_revision.number;
  const count = run.diff?.summary.breaking ?? null;
  return count === null ? { kind: "uncompared", base } : { kind: "count", count, base };
}

/** The revision read's #195 fields (setup.md, model approval gate); absent on an older server. */
export type RevisionBreakingFields = Readonly<{
  import_run_id?: string | undefined;
  breaking?: number | null | undefined;
  breaking_base?: Readonly<{ catalog_revision_id: string; revision: number }> | null | undefined;
}>;

/** A revision's page C3, from the revision read (U102). */
export function revisionBreaking(r: RevisionBreakingFields): Breaking {
  const importRunId = r.import_run_id ?? null;
  if (r.breaking === undefined || r.breaking_base === undefined)
    return { kind: "unknown", importRunId };
  if (r.breaking_base === null) return { kind: "first" };
  // Its import's C3 has the same base and diff, so it can't count either (mms-ux, #386 review).
  if (r.breaking === null) return { kind: "uncompared", base: r.breaking_base.revision };
  return { kind: "count", count: r.breaking, base: r.breaking_base.revision };
}

export type BreakingWords = Readonly<{ line: string; checkbox: string; reason: string }>;

/**
 * U102's callout line, checkbox and Stage's disabled reason. Null only for a known count of 0:
 * every other state needs the acknowledgment before Stage.
 */
export function breakingWords(b: Breaking, rev: number): BreakingWords | null {
  switch (b.kind) {
    case "count": {
      if (b.count === 0) return null;
      const one = b.count === 1;
      return {
        line:
          `Rev ${rev} changes ${plural(b.count, "command or point", "commands or points")} in a way ` +
          `that breaks existing use, compared with rev ${b.base}. Cadence can't tell yet what uses ${one ? "it" : "them"}.`,
        checkbox: one
          ? "I've checked the breaking change"
          : `I've checked the ${plural(b.count, "breaking change")}`,
        reason: `Check the ${one ? "breaking change" : plural(b.count, "breaking change")} first.`,
      };
    }
    case "first":
      return {
        line:
          `Rev ${rev} is the first revision of this catalog, so Cadence has nothing earlier to ` +
          "compare it with and can't tell what it breaks. Check what uses its commands and points " +
          "before you stage.",
        checkbox: `I've checked what rev ${rev} changes`,
        reason: `Check what rev ${rev} changes first.`,
      };
    case "uncompared":
      return {
        line:
          `Cadence couldn't compare rev ${rev} with rev ${b.base}, so this page can't show whether ` +
          "it breaks anything in use. Check what uses its commands and points before you stage.",
        checkbox: `I've checked what rev ${rev} changes`,
        reason: `Check what rev ${rev} changes first.`,
      };
    case "unknown":
      return {
        line:
          `This page can't show whether rev ${rev} breaks anything in use. Check its import's diff ` +
          "before you stage.",
        checkbox: `I've checked rev ${rev}'s diff`,
        reason: `Check rev ${rev}'s diff first.`,
      };
  }
}
