/**
 * TEMPORARY, deleted with 9ac6dc8ee (lead; the director's change-set path, in batches).
 * The legacy route conversion: routes set up on the old routing page are converted to extra routes,
 * one batch of spacecraft per change set, each staged by a click here (ux U79).
 * Contract: api v3.2, `GET|POST /api/console/v1/missions/:mission_id/routes/legacy-conversion`.
 */
import {
  decoders,
  detailsOf,
  isError,
  request,
  spacecraftId,
  type ApiError,
  type ApiResult,
  type Decoded,
  type MissionId,
} from "@/api/index.ts";
import { rejectionSentence } from "@/features/changes/index.ts";
import { formatCount, plural } from "@/ui";

const { array, boolean, integer, nullable, object, string, token } = decoders;

const author = object({ id: token, name: nullable(string) });
const skippedRoute = object({
  routing_rule_id: token,
  reason: decoders.knownText(["transport_has_no_station"] as const),
  spacecraft: object({ id: spacecraftId, name: nullable(string) }),
});
export type SkippedRoute = Decoded<typeof skippedRoute>;

export const conversionReader = object({
  routes_converted: integer,
  routes_total: integer,
  batch_size: integer,
  batches_total: integer,
  /** Null when nothing is left to stage. */
  next_batch: nullable(integer),
  staged_batch: nullable(object({ change_set_id: token, batch: integer, author })),
  unmappable: object({ count: integer, routes: array(skippedRoute, 50) }),
  can_stage: boolean,
});
export type Conversion = Decoded<typeof conversionReader>;

const stagedReader = object({
  change_set_id: token,
  batch: integer,
  batches_total: integer,
  route_count: integer,
  spacecraft_count: integer,
  remaining_route_count: integer,
  /** This batch's skipped routes; the rest staged. */
  unmappable: array(skippedRoute, 5000),
});
export type StagedBatch = Decoded<typeof stagedReader>;

const path = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/routes/legacy-conversion`;

export function fetchConversion(missionId: MissionId): Promise<ApiResult<Conversion>> {
  return request(path(missionId), conversionReader);
}

export function stageNextBatch(missionId: MissionId): Promise<ApiResult<StagedBatch>> {
  return request(path(missionId), stagedReader, { method: "POST" });
}

/** ux U79 words. */
export const CALLOUT =
  "Routes set up on the old routing page can't be changed here until they're converted to extra routes. They're converted in batches, and nothing changes until each batch is applied.";
export const NOT_ADMIN = "Mission admins and organization admins can stage the conversion.";
export const NOTHING_LEFT = "No routes from the old routing page are left to convert.";
export const FAILED = "Couldn't stage the batch. Nothing was changed.";

export const progressLine = (c: Conversion) =>
  `${formatCount(c.routes_converted)} of ${formatCount(c.routes_total)} routes converted.`;

export const stageLabel = (c: Conversion) =>
  c.next_batch === null ? null : `Stage batch ${c.next_batch} of ${c.batches_total}`;

/** A batch already staged; an author without a name is left out, never shown by id. */
export function stagedLine(batch: number, authorName: string | null): string {
  const where = authorName
    ? `Batch ${batch} is staged in ${authorName}'s change set.`
    : `Batch ${batch} is already staged.`;
  return `${where} Apply or discard it before staging the next.`;
}

/** The skipped routes of a batch: one is worded in full; several are counted and listed. */
export function skippedLine(routes: readonly SkippedRoute[]): string | null {
  const [only] = routes;
  if (!only) return null;
  if (routes.length > 1) return `${plural(routes.length, "route")} weren't converted.`;
  const whose = only.spacecraft.name ? `${only.spacecraft.name}'s` : "its";
  return only.reason === "transport_has_no_station"
    ? `1 route wasn't converted: ${whose} transport has no station. Remove it on that spacecraft's routing page.`
    : "1 route wasn't converted. Remove it on its spacecraft's routing page.";
}

/** The spacecraft to link from several skipped routes, once each, in the server's order. */
export function skippedSpacecraft(routes: readonly SkippedRoute[]) {
  const byId = new Map(routes.map((r) => [r.spacecraft.id, r.spacecraft] as const));
  return [...byId.values()];
}

export type StageFailure = Readonly<{
  sentence: string;
  /** An 'Open change set' link goes with it. */
  openSet: boolean;
  /** 'Try again' goes with it. */
  retry: boolean;
}>;

const alreadyStaged = object({ batch: integer, author: nullable(author) });

export function stageFailure(error: ApiError): StageFailure {
  if (isError(error, "conversion_already_staged")) {
    const d = detailsOf(error, alreadyStaged);
    return {
      sentence: d ? stagedLine(d.batch, d.author?.name ?? null) : FAILED,
      openSet: d !== null,
      retry: d === null,
    };
  }
  if (isError(error, "open_change_set_not_empty"))
    return {
      sentence:
        "The mission's open change set has other changes. Apply or discard them first, so this batch is reviewed on its own.",
      openSet: true,
      retry: false,
    };
  if (isError(error, "nothing_to_convert"))
    return { sentence: NOTHING_LEFT, openSet: false, retry: false };
  if (isError(error, "forbidden")) return { sentence: NOT_ADMIN, openSet: false, retry: false };
  if (error.kind === "conflict")
    return { sentence: rejectionSentence(error), openSet: true, retry: false };
  return { sentence: FAILED, openSet: false, retry: true };
}
