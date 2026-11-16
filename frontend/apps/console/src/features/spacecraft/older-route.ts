import type { ChangeSet, StageOp } from "@/features/changes/index.ts";
import type { RoutingRule } from "./detail.ts";
import { stationWord } from "./routes.ts";

/**
 * ux U79 (the director's 'remove legacy rule'): an older route, one set up on the old routing page
 * (origin 'legacy'), leaves through a staged delete of domain's legacy_routing_rule kind. On screen
 * it's always 'older route', never 'legacy'.
 */
export const removeOlderRouteOp = (ruleId: string): StageOp => ({
  kind: "legacy_routing_rule",
  action: "delete",
  entity_id: ruleId,
});

/** The route by its name in quotes, else its station ('INU'); never an id. */
const routeWords = (rule: RoutingRule) =>
  rule.name ? `“${rule.name}”` : stationWord(rule.station);

/** 'Remove older route “qa-pre-routing-175358” · EARENDIL-389' (no spacecraft name: no ' · …'). */
export function olderRouteSummary(rule: RoutingRule, spacecraftName: string | null): string {
  return `Remove older route ${routeWords(rule)}${spacecraftName ? ` · ${spacecraftName}` : ""}`;
}

/** The inline confirm's sentence (ux U79). */
export function removeOlderRouteSentence(rule: RoutingRule, spacecraftName: string | null) {
  const who = spacecraftName || "This spacecraft";
  return `Stage removing ${routeWords(rule)}? ${who} stops using it once the change set is applied.`;
}

/** The older routes whose removal is staged in the open set (inferred from its ops, per api/lead). */
export function stagedRemovals(set: ChangeSet | null | undefined): ReadonlySet<string> {
  const ids = new Set<string>();
  for (const change of set?.changes ?? [])
    for (const op of change.ops)
      if (op.kind === "legacy_routing_rule" && op.action === "delete" && op.entity_id)
        ids.add(op.entity_id);
  return ids;
}
