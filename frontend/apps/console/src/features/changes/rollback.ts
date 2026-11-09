import { decoders, request, type ApiError, type ApiResult, type Decoded } from "@/api";
import {
  errorCode,
  failureOutcome,
  previewReader,
  stageResultReader,
  type StageResult,
} from "./actions.ts";

/** Contract: docs/apogee/api/changes.md § Rollback (DECISIONS #49). */
const { array, integer, nullable, object, string, token } = decoders;

export const rollbackReader = object({
  target: integer,
  head: integer,
  reverts: array(integer, 1000),
  summary: string,
  ops: array(object({ kind: token, entity_id: nullable(string), action: token }), 5000),
  outside: array(object({ kind: token, entity_id: nullable(string) }), 5000),
  preview: nullable(previewReader),
});
export type RollbackPreview = Decoded<typeof rollbackReader>;

const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}/config/rollback`;

/** Previews rolling back to `to`, checked like any change. Writes nothing. */
export function fetchRollback(
  key: Readonly<{ missionId: string; to: number }>,
  signal: AbortSignal,
): Promise<ApiResult<RollbackPreview>> {
  return request(`${base(key.missionId)}?to=${key.to}`, rollbackReader, { signal });
}

/** Stages the rollback as one change in a new change set; review and apply as usual. */
export function stageRollback(missionId: string, to: number): Promise<ApiResult<StageResult>> {
  return request(base(missionId), stageResultReader, {
    method: "POST",
    body: { to },
  });
}

/** The rollback refusals in words (U20 for the rest). */
export function rollbackErrorText(error: ApiError, to: number): string {
  switch (errorCode(error)) {
    case "invalid_rollback_target":
      return `r${to} can't be a rollback target. Pick a revision from r1 up to the one before the live revision.`;
    case "rollback_crosses_legacy": {
      const d = "details" in error ? error.details : null;
      const n =
        d && typeof d === "object" && "newest_legacy_revision" in d
          ? (d as { newest_legacy_revision: unknown }).newest_legacy_revision
          : null;
      return typeof n === "number"
        ? `r${n} was activated outside change sets. You can roll back to r${n}, not past it.`
        : "A revision in this range was activated outside change sets, so the rollback can't cross it.";
    }
    case "change_set_open":
      return "Apply or discard the staged changes first.";
    case "nothing_to_roll_back":
      return `Nothing differs between r${to} and the live revision.`;
    case null:
    default:
      return error.kind === "forbidden"
        ? "You can't roll back configuration here."
        : failureOutcome(error, "staged").sentence;
  }
}
