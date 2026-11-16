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
 */
export type PostureChip = Readonly<{
  key: "crit" | "caution" | "stale" | "never-heard" | "limits-off" | "nominal";
  state: OpState;
  /** null: a word-only chip (limits off, nominal). */
  count: number | null;
  /** The visible word, after the count. */
  word: string;
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
}>;

/** How often telemetry hints may refresh the posture's fleet read (lead 11-16). */
export const POSTURE_FRESHNESS_GAP_MS = 60_000;

const alarms: RouteLocationRaw = { name: "ops.alarms" };

export function postureChips({ counts, limits }: PostureInput): PostureChip[] {
  const chips: PostureChip[] = [];
  if (!limits.configured)
    chips.push({
      key: "limits-off",
      state: "off",
      count: null,
      word: "Ground limits off",
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
        label: `${counts.critical} spacecraft critical`,
        to: alarms,
      });
    if (counts.caution > 0)
      chips.push({
        key: "caution",
        state: "caution",
        count: counts.caution,
        word: "caution",
        label: `${counts.caution} spacecraft caution`,
        to: alarms,
      });
  }
  if (counts.stale > 0)
    chips.push({
      key: "stale",
      state: "stale",
      count: counts.stale,
      word: "stale",
      label: `${counts.stale} spacecraft stale`,
      to: { name: "ops.fleet", query: { state: "stale" } },
    });
  if (counts.never_heard > 0) {
    const none = counts.never_heard === counts.total;
    chips.push({
      key: "never-heard",
      state: "off",
      count: none ? null : counts.never_heard,
      word: none ? "No telemetry yet" : "not heard yet",
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
      label: "Fleet nominal",
      to: { name: "ops.now" },
    });
  return chips;
}
