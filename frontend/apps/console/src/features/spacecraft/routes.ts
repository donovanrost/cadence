import type { MissionId } from "@/api/index.ts";
import {
  decoders,
  isKnown,
  jsonObject,
  request,
  type ApiResult,
  type Decoded,
  type SpacecraftId,
} from "@/api";
import type { StageOp } from "@/features/changes/index.ts";
import type { RoutingRule } from "./detail.ts";

/**
 * U79: a spacecraft's extra route (domain's `spacecraft_route` kind), on Setup › Spacecraft › one
 * › Routing. Tags come from the read's `origin`; Edit and Remove… key on `route_id`.
 */
export type RouteTag = Readonly<{
  label: "From profile" | "This spacecraft only";
  /** A quiet second line on the row (ux: legacy rules). */
  note: string | null;
  /** Why the row has no Edit / Remove… (ux A6: said, not a disabled button). */
  reason: string | null;
}>;

/** The tag for a rule; null when the server doesn't say (older server, or a new origin). */
export function routeTag(rule: RoutingRule): RouteTag | null {
  const origin = rule.origin;
  if (origin === undefined || !isKnown(origin)) return null;
  if (origin === "profile") return { label: "From profile", note: null, reason: null };
  if (origin === "spacecraft") return { label: "This spacecraft only", note: null, reason: null };
  // ux (U79, lead's ruling): a legacy rule is this spacecraft's only, set up before extra routes.
  return {
    label: "This spacecraft only",
    note: "Set up on the old routing page.",
    reason: "Older routes can't be edited here until they're converted.",
  };
}

/** The extra route a row belongs to, when it can be edited and removed here. */
export const extraRouteId = (rule: RoutingRule): string | null =>
  rule.origin === "spacecraft" ? (rule.route_id ?? null) : null;

/**
 * The rows that carry Edit / Remove…, each with its extra route: the first leg row of each route
 * (its two legs are two rows with the same route_id; one pair of actions per route).
 */
export function actionRows(rules: readonly RoutingRule[]): ReadonlyMap<string, string> {
  const seen = new Set<string>();
  const rows = new Map<string, string>();
  for (const rule of rules) {
    const id = extraRouteId(rule);
    if (id === null || seen.has(id)) continue;
    seen.add(id);
    rows.set(rule.id, id);
  }
  return rows;
}

/** A station in the summary's words (U25: names, never ids): its code, else its name. */
export function stationWord(
  station: Readonly<{ code: string | null; name: string | null }> | null | undefined,
): string {
  return station?.code || station?.name || "a removed station";
}

/** U79 change-set lines: "Add extra route INU · EARENDIL-389". */
export const routeSummary = (
  verb: "Add" | "Edit" | "Remove",
  station: string,
  spacecraft: string,
): string => `${verb} extra route ${station} · ${spacecraft}`;

/**
 * U79 Edit / Remove lines (ux): a named route quotes its rendered name, so two routes at one station
 * read apart ('Edit extra route “Fairbanks (Demo) — uplink” · EARENDIL-389'). A name that is the
 * default '<station> · <spacecraft>' reads as unnamed (the station form), and a name that already
 * holds the spacecraft's doesn't repeat it.
 */
export function routeChangeSummary(
  verb: "Edit" | "Remove",
  renderedName: string | null,
  station: string,
  spacecraft: string,
): string {
  const name = renderedName?.trim() ?? "";
  if (name === "" || name === `${station} · ${spacecraft}`)
    return routeSummary(verb, station, spacecraft);
  return name.includes(spacecraft)
    ? `${verb} extra route “${name}”`
    : `${verb} extra route “${name}” · ${spacecraft}`;
}

export const removeRouteOp = (routeId: string): StageOp => ({
  kind: "spacecraft_route",
  action: "delete",
  entity_id: routeId,
});

const extraRouteReader = decoders.object({
  id: decoders.token,
  // Field values are read through the kind schema's paths.
  document: jsonObject,
});
export type ExtraRoute = Decoded<typeof extraRouteReader>;

/** U79 (api B): one extra route's stored document, for KindEditor's Edit. */
export function fetchExtraRoute(
  key: Readonly<{ missionId: MissionId; spacecraftId: SpacecraftId; routeId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<ExtraRoute>> {
  const m = encodeURIComponent(key.missionId);
  const sc = encodeURIComponent(key.spacecraftId);
  return request(
    `/missions/${m}/spacecraft/${sc}/routes/${encodeURIComponent(key.routeId)}`,
    extraRouteReader,
    { signal },
  );
}
