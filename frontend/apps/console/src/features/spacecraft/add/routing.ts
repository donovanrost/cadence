import type { ProfileDetail, ProfileRule } from "@/features/profiles/index.ts";
import { formatCount, plural } from "@/ui";

/** Routes one rule makes for each spacecraft: stations × legs (profile-routing.md §2.1). */
export const routesPerSpacecraft = (rule: ProfileRule) =>
  rule.enabled ? rule.stations.length * rule.legs.length : 0;

export type RoutingSummary = Readonly<{
  kind: "per_spacecraft" | "none" | "rules";
  lines: readonly string[];
  total: string | null;
}>;

/**
 * AddSpacecraft.md step 03: what routing the new spacecraft get from their profile. Rule lines read
 * "Rule `Block 2 · all stations` generates 6 routes per spacecraft"; the total "300 routes for 50
 * spacecraft".
 */
export function routingSummary(
  detail: Pick<ProfileDetail, "rules" | "routing_model">,
  count: number,
): RoutingSummary {
  if (detail.routing_model === "per_spacecraft")
    return { kind: "per_spacecraft", lines: [], total: null };
  const rules = detail.rules.filter((r) => r.enabled);
  if (rules.length === 0) return { kind: "none", lines: [], total: null };
  const lines = rules.map(
    (r) => `Rule ${r.label} generates ${plural(routesPerSpacecraft(r), "route")} per spacecraft`,
  );
  const per = rules.reduce((n, r) => n + routesPerSpacecraft(r), 0);
  return {
    kind: "rules",
    lines,
    total: `${plural(per * count, "route")} for ${formatCount(count)} spacecraft`,
  };
}
