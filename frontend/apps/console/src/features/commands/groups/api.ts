import {
  decoders as d,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api/index.ts";

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

const perTarget = d.object({
  spacecraft_id: d.token,
  result,
  reason: d.optional(failureReason),
  next_contact: d.optional(d.nullable(nextContact)),
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

export function fetchGroups(
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
  return request(
    `${groupsBase(missionId)}${qs ? `?${qs}` : ""}`,
    d.array(groupRow, 1_000),
    signal ? { signal } : {},
  );
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
): Promise<WriteOutcome<Created>> {
  return outcomeOf(
    await request(groupsBase(missionId), created, {
      method: "POST",
      body: { ...draft, preflight_digest: digest, operation_id: operationId },
    }),
  );
}
