import type { RouteLocationRaw } from "vue-router";
import type { OpState } from "@/ui";

/**
 * Fleet posture chips (ux information-architecture.md §Top bar, ca31e877a). Shared by the top
 * bar's posture cluster and the dashboard cockpit:
 * - Only non-zero states appear, worst first: `◆ 2 crit · ▲ 1 caution · ▨ 3 stale`.
 * - Ground limits not installed: `○ Ground limits off` replaces crit and caution; stale still counts.
 * - Never heard (ux fb5e5ded0, U9 words): a last chip `○ 6 not heard yet`, or `○ No telemetry yet`
 *   when no spacecraft has been heard. It isn't a problem state, but it blocks the nominal claim.
 * - `■ Fleet nominal` only when there's nothing else, so never while anything is stale or unheard.
 * - An empty mission (no spacecraft) shows nothing; Now covers the empty fleet (ux).
 */
export type PostureChip = Readonly<{
  key: "crit" | "caution" | "stale" | "never-heard" | "unheard-recently" | "limits-off" | "nominal";
  state: OpState;
  /** null: a word-only chip (limits off, nominal). */
  count: number | null;
  /** The visible word, after the count. */
  word: string;
  /** Compact (below 1600px, or the top bar's first give-way step): "" for a counted chip. */
  short: string;
  /** Accessible name and title: "2 spacecraft critical". */
  label: string;
  to: RouteLocationRaw;
}>;

export type PostureInput = Readonly<{
  counts: Readonly<{
    critical: number;
    caution: number;
    stale: number;
    never_heard: number;
    total: number;
  }>;
  limits: Readonly<{ configured: boolean }>;
  /** /counts' posture says whether telemetry history answered; GET /fleet's counts don't. */
  telemetry?: "ok" | "degraded" | "unrecognized" | undefined;
}>;

const alarms: RouteLocationRaw = { name: "ops.alarms" };

/** ux fb5e5ded0 (2): degraded, Cadence can't tell stale from never heard, so they're one chip. */
export const DEGRADED_SENTENCE =
  "Cadence couldn't read telemetry history, so it can't tell which of these were heard before the restart.";

export function postureChips({ counts, limits, telemetry }: PostureInput): PostureChip[] {
  if (counts.total === 0) return [];
  const chips: PostureChip[] = [];
  if (!limits.configured)
    chips.push({
      key: "limits-off",
      state: "off",
      count: null,
      word: "Ground limits off",
      short: "Limits off",
      label: "Ground limits off",
      to: { name: "setup.apps" },
    });
  else {
    if (counts.critical > 0)
      chips.push({
        key: "crit",
        state: "crit",
        count: counts.critical,
        word: "crit",
        short: "",
        label: `${counts.critical} spacecraft critical`,
        to: alarms,
      });
    if (counts.caution > 0)
      chips.push({
        key: "caution",
        state: "caution",
        count: counts.caution,
        word: "caution",
        short: "",
        label: `${counts.caution} spacecraft in caution`,
        to: alarms,
      });
  }
  const unheard = counts.stale + counts.never_heard;
  if (telemetry === "degraded") {
    if (unheard > 0)
      chips.push({
        key: "unheard-recently",
        state: "stale",
        count: unheard,
        word: "not heard recently",
        short: "",
        label: `${unheard} spacecraft not heard recently. ${DEGRADED_SENTENCE}`,
        to: { name: "ops.fleet", query: { state: "stale,never_heard" } },
      });
  } else if (counts.stale > 0)
    chips.push({
      key: "stale",
      state: "stale",
      count: counts.stale,
      word: "stale",
      short: "",
      label: `${counts.stale} spacecraft stale`,
      to: { name: "ops.fleet", query: { state: "stale" } },
    });
  if (telemetry !== "degraded" && counts.never_heard > 0) {
    const none = counts.never_heard === counts.total;
    chips.push({
      key: "never-heard",
      state: "off",
      count: none ? null : counts.never_heard,
      word: none ? "No telemetry yet" : "not heard yet",
      short: none ? "No telemetry yet" : "",
      label: none ? "No telemetry yet" : `${counts.never_heard} spacecraft not heard yet`,
      to: { name: "ops.fleet", query: { state: "never_heard" } },
    });
  }
  if (chips.length === 0)
    chips.push({
      key: "nominal",
      state: "nominal",
      count: null,
      word: "Fleet nominal",
      short: "Nominal",
      label: "Fleet nominal",
      to: { name: "ops.now" },
    });
  return chips;
}

/** The posture keeps its words from 1600px (ux IA §Top bar, 9c49c76ab). */
export const POSTURE_WIDE_QUERY = "(min-width: 100rem)";
