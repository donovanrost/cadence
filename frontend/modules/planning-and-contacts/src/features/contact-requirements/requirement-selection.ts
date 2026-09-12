import type { RequirementDetail } from "./OpsContactRequirementShow.contracts";
import { decision, identifier } from "./requirement-detail";

export const SELECTION_LIMIT = 100;
export const selectionStorageKey = "cadence.requirement-selection.v1";
export const selectionIdentity = (d: RequirementDetail) =>
  JSON.stringify([
    d.context.actor_id,
    d.context.organization_id,
    d.context.mission_id,
    d.requirement.id,
    d.requirement.version,
    d.requirement.content_sha256,
    d.selected_run?.id ?? null,
  ]);
export function restoreSelection(
  storage: Storage,
  d: RequirementDetail,
): { ids: string[]; changed: boolean } {
  const raw = storage.getItem(selectionStorageKey);
  if (!raw) return { ids: [], changed: false };
  try {
    if (raw.length > 100_000) throw new Error("Oversized selection");
    const saved = JSON.parse(raw);
    if (saved.identity !== selectionIdentity(d) || !d.context.actor_id || !d.selected_run)
      throw new Error("Review identity changed");
    if (
      !Array.isArray(saved.ids) ||
      saved.ids.length > SELECTION_LIMIT ||
      !saved.ids.every(identifier) ||
      new Set(saved.ids).size !== saved.ids.length
    )
      throw new Error("Invalid selection");
    return { ids: saved.ids, changed: false };
  } catch {
    storage.removeItem(selectionStorageKey);
    return { ids: [], changed: true };
  }
}
export function persistSelection(storage: Storage, d: RequirementDetail, ids: string[]) {
  if (ids.length > SELECTION_LIMIT || !ids.every(identifier) || new Set(ids).size !== ids.length)
    throw new Error("Invalid selection");
  if (!ids.length) storage.removeItem(selectionStorageKey);
  else
    storage.setItem(selectionStorageKey, JSON.stringify({ identity: selectionIdentity(d), ids }));
}
export function completedSelection(d: RequirementDetail, event: unknown): boolean {
  if (!event || typeof event !== "object") return false;
  const { actionId, result } = event as any;
  const expected = decision(d).requirement_evidence;
  return (
    actionId === "create-plan" &&
    result?.actorId === d.context.actor_id &&
    result?.planningRunId === d.selected_run?.id &&
    identifier(result?.contactPlanId) &&
    Boolean(result?.requirementEvidence) &&
    Object.entries(expected).every(([key, value]) => result.requirementEvidence[key] === value)
  );
}
