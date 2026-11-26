import { decoders as d, request, type ApiResult, type Decoded, type MissionId } from "@/api";
import { expiredReader } from "./lifecycle.ts";
import { base, type PlanState, planState, stationReader, stationKey } from "./plans-api.ts";
import { longestGapReader, planDetailReader, type PlanDetail } from "./plan-detail-api.ts";
import { draftRunReader, startReader } from "./drafting-api.ts";

/** Contracts: docs/apogee/api/scheduling.md §4: submit, execute, send back, edit (S4/S5) and repair (S8). */

export type Acknowledgement = Readonly<{ requirement_id: string; reason: string }>;

const submitReader = d.object({
  plan_id: d.token,
  /** #257 (api): the version submit put up (a sent-back draft's resubmit cuts the next one). */
  version: d.optional(d.integer),
  state: planState,
  /** #257: submit only submits; "executing" and "replayed" are older servers' answers. */
  outcome: d.knownText(["pending_approval", "executing", "replayed"] as const),
  /** #257: the original answer to a repeated operation_id (U97: shown as this one's result). */
  replayed: d.optional(d.boolean),
  /** U61: passes left out because their booking window had closed (#273); absent on older servers. */
  expired: (value: unknown, path?: string) =>
    value === undefined ? null : expiredReader(value, path),
});
export type SubmitResult = Decoded<typeof submitReader>;

/** S5 submit (#257: only submits, for everyone). U76: the optional note goes with the submission. */
export function submitPlan(
  missionId: MissionId,
  plan: Readonly<{ id: string; version: number }>,
  operationId: string,
  acknowledgements: readonly Acknowledgement[],
  note?: string,
): Promise<ApiResult<SubmitResult>> {
  return request(`${base(missionId)}/${encodeURIComponent(plan.id)}/submit`, submitReader, {
    method: "POST",
    body: {
      expected_version: plan.version,
      operation_id: operationId,
      ...(acknowledgements.length > 0 ? { acknowledgements } : {}),
      ...(note ? { note } : {}),
    },
  });
}

const approveReader = d.object({
  plan_id: d.token,
  state: planState,
  /** U97/U20: "Approved" only on outcome approved; anything else says no approval was recorded. */
  outcome: d.knownText(["approved"] as const),
  replayed: d.optional(d.boolean),
  expired: (value: unknown, path?: string) =>
    value === undefined ? null : expiredReader(value, path),
});
export type ApproveResult = Decoded<typeof approveReader>;

/**
 * #257 approve (api): an org admin approves `plan.version` and booking starts (202). The note is
 * recorded on the decision; the approver's gap reasons on the approval's exceptions.
 */
export function approvePlan(
  missionId: MissionId,
  plan: Readonly<{ id: string; version: number }>,
  operationId: string,
  acknowledgements: readonly Acknowledgement[],
  decisionNote?: string,
  /** #273: the plan read's expired_digest, as the approver saw it; absent means they saw none closed. */
  expectedExpiredDigest?: string,
): Promise<ApiResult<ApproveResult>> {
  return request(`${base(missionId)}/${encodeURIComponent(plan.id)}/approve`, approveReader, {
    method: "POST",
    body: {
      expected_version: plan.version,
      operation_id: operationId,
      ...(acknowledgements.length > 0 ? { acknowledgements } : {}),
      ...(decisionNote ? { decision_note: decisionNote } : {}),
      ...(expectedExpiredDigest !== undefined
        ? { expected_expired_digest: expectedExpiredDigest }
        : {}),
    },
  });
}

/** Resume an interrupted (or approved, never started) execution; items are idempotent. */
export function executePlan(missionId: MissionId, planId: string) {
  return request(
    `${base(missionId)}/${encodeURIComponent(planId)}/execute`,
    d.object({ plan_id: d.token, state: planState }),
    {
      method: "POST",
      body: {},
    },
  );
}

/** Acknowledgement reasons must be 10–2000 characters (scheduling.md S5). */
export const REASON_MIN = 10;
export const REASON_MAX = 2000;

/** S4 edit: next plan version with the selection changed; returns the new plan detail. */
/** Send back (api c7c7b277): a pending_approval plan returns to draft with the reviewer's reason. */
export function rejectPlan(
  missionId: MissionId,
  plan: Readonly<{ id: string; version: number }>,
  reason: string,
): Promise<ApiResult<PlanDetail>> {
  return request(`${base(missionId)}/${encodeURIComponent(plan.id)}/reject`, planDetailReader, {
    method: "POST",
    body: { expected_version: plan.version, reason },
  });
}

export function editPlan(
  missionId: MissionId,
  plan: Readonly<{ id: string; version: number }>,
  change: Readonly<{ add?: readonly string[]; remove?: readonly string[] }>,
): Promise<ApiResult<PlanDetail>> {
  return request(`${base(missionId)}/${encodeURIComponent(plan.id)}/versions`, planDetailReader, {
    method: "POST",
    body: { expected_version: plan.version, ...change },
  });
}

export const alternativesReader = d.object({
  plan_id: d.token,
  version: d.integer,
  spacecraft_id: d.token,
  rule_met: d.boolean,
  contacts: d.object({ have: d.integer, need: d.nullable(d.integer) }),
  /** The spacecraft's longest gap today (domain c38bb5de), for "6h10 → 3h05". */
  longest_gap: longestGapReader,
  alternatives: d.array(
    d.object({
      snapshot_id: d.token,
      requirement_id: d.nullable(d.token),
      station: stationReader,
      starts_at: d.timestamp,
      ends_at: d.timestamp,
      synthetic: d.boolean,
      effect: d.object({
        rule_met_after: d.boolean,
        contacts_after: d.object({ have: d.integer, need: d.nullable(d.integer) }),
        clashes_with: d.array(d.token),
        longest_gap_after_seconds: d.optional(d.nullable(d.integer)),
      }),
    }),
    2_000,
  ),
});
export type Alternatives = Decoded<typeof alternativesReader>;
export type Alternative = Alternatives["alternatives"][number];

/** S4: unselected opportunities for one spacecraft with their effect (nothing is written). */
export function fetchAlternatives(
  missionId: MissionId,
  planId: string,
  spacecraftId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Alternatives>> {
  return request(
    `${base(missionId)}/${encodeURIComponent(planId)}/alternatives?spacecraft_id=${encodeURIComponent(spacecraftId)}`,
    alternativesReader,
    signal ? { signal } : {},
  );
}

/** Plans whose selection can still change (editing a plan in review returns it to draft). */
export const editableStates: readonly PlanState[] = ["draft", "pending_approval"];

const repairPass = d.object({
  snapshot_id: d.token,
  spacecraft_id: d.nullable(d.token),
  station: stationReader,
  starts_at: d.timestamp,
  ends_at: d.timestamp,
});

export const repairReader = d.object({
  run: draftRunReader,
  plan: d.nullable(planDetailReader),
  source_plan: d.object({ id: d.token, version: d.integer }),
  diff: d.nullable(
    d.object({
      kept: d.array(repairPass, 5_000),
      moved: d.array(
        d.object({
          spacecraft_id: d.nullable(d.token),
          from: repairPass,
          to: repairPass,
          offset_s: d.integer,
        }),
        5_000,
      ),
      dropped: d.array(repairPass, 5_000),
      added: d.array(repairPass, 5_000),
      /** #56: lost passes a live single booking already covers (sent nothing); absent → []. */
      covered: (value: unknown, path?: string) =>
        value === undefined
          ? []
          : d.array(
              d.object({
                snapshot_id: d.token,
                spacecraft_id: d.nullable(d.token),
                station: stationReader,
                starts_at: d.timestamp,
                ends_at: d.timestamp,
                covered_by: d.token,
              }),
              5_000,
            )(value, path),
      totals: (value: unknown) => value,
    }),
  ),
});
export type Repair = Decoded<typeof repairReader>;

/** States a plan must be in to be repaired (scheduling.md S8). */
export const repairableStates: readonly PlanState[] = [
  "executing",
  "partially_reserved",
  "failed",
  "interrupted",
];

/**
 * S8: start a repair run off the request; progress via scheduling_progress {kind: "draft"}.
 * `window` (ISO-8601) narrows the repair; without it the server uses now → the plan's horizon end,
 * which can exceed the policy's repair window (422 fleet_repair_horizon_exceeded).
 */
export function startRepair(
  missionId: MissionId,
  planId: string,
  operationId: string,
  window?: Readonly<{ from: string; to: string }>,
) {
  return request(`${base(missionId)}/${encodeURIComponent(planId)}/repairs`, startReader, {
    method: "POST",
    body: { operation_id: operationId, ...(window ? { from: window.from, to: window.to } : {}) },
  });
}

export function fetchRepair(
  missionId: MissionId,
  runId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Repair>> {
  return request(
    `${base(missionId)}/repairs/${encodeURIComponent(runId)}`,
    repairReader,
    signal ? { signal } : {},
  );
}

/** One row per window: the same provider window can come back once per requirement (ux K1 #5). */
export function distinctWindows(list: readonly Alternative[]): Alternative[] {
  const seen = new Set<string>();
  return list.filter((a) => {
    const key = `${stationKey(a.station)}|${a.starts_at}|${a.ends_at}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
