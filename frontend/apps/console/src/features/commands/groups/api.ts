import {
  decoders as d,
  DecodeError,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api/index.ts";
import { groupUplinkReader } from "@/features/contacts/readiness.ts";

/**
 * Command groups (docs/apogee/api/commanding.md §Command groups, DECISIONS #29–#31): preflight,
 * submit and the list. The show shape and decisions live in show.ts.
 */

export type DraftTarget = Readonly<{ spacecraft_id: string; source_endpoint_id: string | null }>;
export type DraftCommand = Readonly<{ command_id: string; argument_values_json: string }>;
export type TargetChip = Readonly<{ key: string; value: string | number | readonly string[] }>;
export type Draft = Readonly<{
  title: string;
  log_entry: string;
  targets: readonly DraftTarget[];
  target_query: Readonly<{ chips: readonly TargetChip[]; explicit: readonly string[] }>;
  commands: readonly DraftCommand[];
  not_before: string | null;
  expires_at: string | null;
  priority: number;
  requested_approver_user_id: string | null;
  sent_back_from: string | null;
}>;

/** #60: an operator's acknowledgement of one ackable HOLD, tied to that HOLD's facts. */
export type HoldAck = Readonly<{ key: string; hold_basis: string | null; note: string }>;
export const HOLD_NOTE_MAX = 1000;

export const checkResults = ["go", "hold", "no_go"] as const;
export type CheckResult = (typeof checkResults)[number];
const result = d.oneOf(checkResults);

const memberFailure = d.object({ position: d.integer, command_id: d.token, reason: d.token });
export type MemberFailure = Decoded<typeof memberFailure>;
/** Identity failures are one code per target; catalog failures list the failing commands. */
const failureReason: Reader<string | readonly MemberFailure[]> = (value, path = "") =>
  typeof value === "string" ? d.token(value, path) : d.array(memberFailure, 16)(value, path);

const nextContact = d.object({ station_code: d.string, aos: d.timestamp, los: d.timestamp });
export type NextContact = Decoded<typeof nextContact>;

/** A route named by an identity NO-GO (DECISIONS #41), so the screen can link to its routing. */
const route = d.object({
  id: d.token,
  name: d.nullable(d.string),
  direction: d.nullable(d.token),
  profile_id: d.nullable(d.token),
});
export type UplinkRoute = Decoded<typeof route>;

const perTarget = d.object({
  spacecraft_id: d.token,
  result,
  reason: d.optional(d.nullable(failureReason)),
  next_contact: d.optional(d.nullable(nextContact)),
  routes: d.optional(d.array(route, 100)),
});

const twoPersonReason = d.object({
  key: d.token,
  command_id: d.optional(d.token),
  name: d.optional(d.string),
  targets: d.optional(d.integer),
  threshold: d.optional(d.integer),
});
export type TwoPersonReason = Decoded<typeof twoPersonReason>;

/** One reader for every check's evidence: each check fills its own keys (the rest are absent). */
const evidence = d.object({
  count: d.optional(d.integer),
  command_request_ids: d.optional(d.array(d.token, 5_000)),
  until: d.optional(d.nullable(d.timestamp)),
  reasons: d.optional(d.array(twoPersonReason, 100)),
  max_targets: d.optional(d.integer),
  max_commands: d.optional(d.integer),
  max_members: d.optional(d.integer),
  targets: d.optional(d.integer),
  commands: d.optional(d.integer),
});

const check = d.object({
  key: d.token,
  result,
  per_target: d.array(perTarget, 1_000),
  evidence,
  /** DECISIONS #60: null unless HOLD. false = hard (clear it); true = an operator may ack it. */
  ackable: d.optional(d.nullable(d.boolean)),
  /** That HOLD's facts, hashed: an ack counts only while it still matches. */
  hold_basis: d.optional(d.nullable(d.string)),
});
export type PreflightCheck = Decoded<typeof check>;

export const preflightReader = d.object({
  valid: d.boolean,
  digest: d.nullable(d.string),
  members: d.integer,
  second_go_required: d.nullable(d.boolean),
  targets: d.array(
    d.object({
      index: d.integer,
      spacecraft_id: d.token,
      source_endpoint_id: d.nullable(d.token),
      name: d.nullable(d.string),
      scid: d.nullable(d.integer),
      failure: d.nullable(d.token),
    }),
    1_000,
  ),
  checks: d.array(check, 20),
});
export type Preflight = Decoded<typeof preflightReader>;

export const memberStages = [
  "awaiting_go",
  "queued_for_contact",
  "radiating",
  "executed",
  "verified",
  "no_verifier",
  "verify_failed",
  "release_failed",
  "indeterminate",
  "canceled",
  "rejected",
  "excluded",
] as const;
export type MemberStage = (typeof memberStages)[number];
export const memberStage = d.oneOf(memberStages);

/** `{stage: target count}`: keys must be known stages. */
export const progressReader: Reader<Partial<Record<MemberStage, number>>> = (value, path = "") => {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new DecodeError(path, "object");
  const out: Partial<Record<MemberStage, number>> = {};
  for (const [key, count] of Object.entries(value))
    out[memberStage(key, `${path}.${key}`)] = d.integer(count, `${path}.${key}`);
  return out;
};

export const groupStates = [
  "approval_pending",
  "queued",
  "rejected",
  "sent_back",
  "aborted",
] as const;
export type GroupState = (typeof groupStates)[number];
export const actor = d.object({ actor_kind: d.token, user_id: d.nullable(d.token) });
export const groupRow = d.object({
  id: d.token,
  state: d.oneOf(groupStates),
  title: d.string,
  requested_by: actor,
  requested_at: d.timestamp,
  requested_approver_user_id: d.nullable(d.token),
  member_count: d.integer,
  target_count: d.integer,
  command_count: d.integer,
  second_go_required: d.boolean,
  awaiting_me: d.boolean,
  operation_id: d.nullable(d.string),
  // cfef9e9a: null unless state is queued. `finished` = every target final (not success).
  progress: d.optional(d.nullable(progressReader)),
  finished: d.optional(d.nullable(d.boolean)),
  /** U33: the pass this group is queued for and its readiness; null with no pass yet. */
  uplink: d.optional(d.nullable(groupUplinkReader)),
});
export type GroupRow = Decoded<typeof groupRow>;

export const groupsBase = (missionId: string) =>
  `/missions/${encodeURIComponent(missionId)}/command-groups`;

export function fetchPreflight(
  missionId: string,
  draft: Draft,
  signal?: AbortSignal,
): Promise<ApiResult<Preflight>> {
  return request(`${groupsBase(missionId)}/preflight`, preflightReader, {
    method: "POST",
    body: draft,
    ...(signal ? { signal } : {}),
  });
}

export type GroupListQuery = Readonly<{
  awaitingMe?: boolean;
  mine?: boolean;
  operationId?: string;
  states?: readonly GroupState[];
}>;

const groupList = d.object({ groups: d.array(groupRow, 1_000) });

/** `{data: {groups: [...]}}`; the screens want the rows. */
export async function fetchGroups(
  missionId: string,
  query: GroupListQuery,
  signal?: AbortSignal,
): Promise<ApiResult<readonly GroupRow[]>> {
  const p = new URLSearchParams();
  if (query.awaitingMe) p.set("awaiting_me", "true");
  if (query.mine) p.set("mine", "true");
  if (query.operationId) p.set("operation_id", query.operationId);
  if (query.states?.length) p.set("state", query.states.join(","));
  const qs = p.toString();
  const result = await request(
    `${groupsBase(missionId)}${qs ? `?${qs}` : ""}`,
    groupList,
    signal ? { signal } : {},
  );
  return result.ok ? { ok: true, value: result.value.groups } : result;
}

/** Write outcomes (ux U20): rejected = nothing changed; unclear = check, never blind retry. */
export type WriteOutcome<T> =
  | { status: "done"; value: T }
  | { status: "rejected"; error: ApiError }
  | { status: "unclear"; error: ApiError };

export function outcomeOf<T>(result: ApiResult<T>): WriteOutcome<T> {
  if (result.ok) return { status: "done", value: result.value };
  const e = result.error;
  const rejected =
    e.kind === "forbidden" ||
    e.kind === "not_found" ||
    e.kind === "conflict" ||
    e.kind === "invalid" ||
    e.kind === "unauthenticated";
  return rejected ? { status: "rejected", error: e } : { status: "unclear", error: e };
}

const created = d.object({ id: d.token, state: d.oneOf(groupStates) });
export type Created = Decoded<typeof created>;

export async function submitGroup(
  missionId: string,
  draft: Draft,
  digest: string,
  operationId: string,
  acknowledgedHolds: readonly HoldAck[] = [],
): Promise<WriteOutcome<Created>> {
  return outcomeOf(
    await request(groupsBase(missionId), created, {
      method: "POST",
      body: {
        ...draft,
        preflight_digest: digest,
        operation_id: operationId,
        acknowledged_holds: acknowledgedHolds,
      },
    }),
  );
}

/** Compose's endpoint picker (commanding.md §GET /command-endpoints, DECISIONS #41). */
const targetEndpoints = d.object({
  spacecraft_id: d.token,
  resolved_source_endpoint_id: d.nullable(d.token),
  failure: d.nullable(d.token),
  routes: d.array(route, 100),
  endpoints: d.array(
    d.object({
      id: d.token,
      name: d.nullable(d.string),
      scid: d.nullable(d.integer),
      managed: d.boolean,
    }),
    50,
  ),
});
export type TargetEndpoints = Decoded<typeof targetEndpoints>;
const endpointList = d.object({ spacecraft: d.array(targetEndpoints, 1_000) });

export async function fetchEndpoints(
  missionId: string,
  spacecraftIds: readonly string[],
  signal?: AbortSignal,
): Promise<ApiResult<readonly TargetEndpoints[]>> {
  const p = new URLSearchParams({ spacecraft_ids: spacecraftIds.join(",") });
  const result = await request(
    `/missions/${encodeURIComponent(missionId)}/command-endpoints?${p.toString()}`,
    endpointList,
    signal ? { signal } : {},
  );
  return result.ok ? { ok: true, value: result.value.spacecraft } : result;
}
