import type { MissionId } from "@/api/index.ts";
import { expiryReader } from "./expiryReader.ts";
import { resolvedArgumentsReader } from "./resolved.ts";
import { withdrawnTargetFields } from "./withdrawn.ts";
import {
  scid as scidReader,
  decoders as d,
  DecodeError,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  type Reader,
  isKnown,
  type Unrecognized,
} from "@/api/index.ts";
import { groupUplinkReader } from "@/features/contacts/readiness.ts";

/**
 * Command groups (docs/apogee/api/commanding.md §Command groups, DECISIONS #29–#31): preflight,
 * submit and the list. The show shape and decisions live in show.ts.
 */

export type DraftTarget = Readonly<{ spacecraft_id: string; source_endpoint_id: string | null }>;
/** A target's own argument values (B2; api f1bed1880): overrides the command's for that target. */
export type DraftPerTarget = Readonly<{ spacecraft_id: string; argument_values_json: string }>;
export type DraftCommand = Readonly<{
  command_id: string;
  argument_values_json: string;
  per_target?: readonly DraftPerTarget[];
}>;
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

/** #61: second_go = "needs a second GO" (two_person only); informational, never blocks. */
export const checkResults = ["go", "second_go", "hold", "no_go"] as const;
export type CheckResult = (typeof checkResults)[number];
const result = d.oneOf(checkResults);

const memberFailure = d.object({
  position: d.integer,
  command_id: d.token,
  // free-text: preflight's catalog failure key, worded in checks.ts with a fallback
  reason: d.token,
});
export type MemberFailure = Decoded<typeof memberFailure>;
/** Identity failures are one code per target; catalog failures list the failing commands. */
const failureReason: Reader<string | readonly MemberFailure[]> = (value, path = "") =>
  typeof value === "string" ? d.token(value, path) : d.array(memberFailure, 16)(value, path);

const nextContact = d.object({
  // free-text: a station call sign, not a vocabulary
  station_code: d.string,
  /** f57e5fff: the station's ref, to name its provider from the stations index. */
  ground_station_ref: d.optional(d.nullable(d.token)),
  aos: d.timestamp,
  los: d.timestamp,
});
export type NextContact = Decoded<typeof nextContact>;

/** A route named by an identity NO-GO (DECISIONS #41), so the screen can link to its routing. */
/** commanding.md §GET /command-endpoints: why a target has no uplink endpoint. */
export const endpointFailures = ["no_uplink_route", "multiple_primary_uplink_routes"] as const;
export type EndpointFailure = (typeof endpointFailures)[number];
const endpointFailure = d.nullable(d.knownText(endpointFailures));

const route = d.object({
  id: d.token,
  name: d.nullable(d.string),
  // free-text: decoded for completeness, never shown or branched on (no vocabulary in the contract)
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
  ...withdrawnTargetFields,
});

/** commanding.md: why a group needs a second GO (DECISIONS #61). */
export const twoPersonReasonKeys = [
  "hazardous_command",
  "critical_command",
  "policy_hint",
  "fleet_reach",
] as const;
const twoPersonReason = d.object({
  key: d.knownText(twoPersonReasonKeys),
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

/** commanding.md preflight: the checks the console labels; a newer one still shows, by its key. */
export const checkKeys = [
  "identity",
  "catalog",
  "size",
  "conflicts",
  "contact",
  "two_person",
  "changed_since_submit",
  // U109 (#546): a target on a composition that's no longer approved; label "Composition".
  "model_approval_withdrawn",
] as const;
export type CheckKey = (typeof checkKeys)[number];
/** A check's key as text: acks and lists key by it, and an ack sends it back to the server. */
export const checkKeyText = (key: CheckKey | Unrecognized): string =>
  isKnown(key) ? key : key.unrecognized;

const check = d.object({
  key: d.knownText(checkKeys),
  result,
  per_target: d.array(perTarget, 1_000),
  evidence,
  /** DECISIONS #60: null unless HOLD. false = hard (clear it); true = an operator may ack it. */
  ackable: d.optional(d.nullable(d.boolean)),
  /** That HOLD's facts, hashed: an ack counts only while it still matches. */
  hold_basis: d.optional(d.nullable(d.string)),
});
export type PreflightCheck = Decoded<typeof check>;

/** U51 (api): a catalog revision as preflight names it; label is set whenever the revision exists. */
const revision = d.object({ number: d.nullable(d.integer), label: d.nullable(d.string) });
/** One verifier as the catalog defines it (commanding.md command.verifiers; the rest unread). */
const verifier = d.object({
  id: d.token,
  name: d.string,
  phase: d.knownText(["acceptance", "start", "completion", "custom"] as const),
  timeout_ms: d.nullable(d.integer),
});
/**
 * U51: one group per distinct verifier set for a command, largest first; `verifiers: []` is "no
 * verifier". Targets with that command's Catalog NO-GO are in no group.
 */
export const verifierGroupReader = d.object({
  verifiers: d.array(verifier, 100),
  catalog_revisions: d.array(revision, 100),
  spacecraft_ids: d.array(d.token, 10_000),
});
export type VerifierGroup = Decoded<typeof verifierGroupReader>;
export type CatalogRevision = Decoded<typeof revision>;

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
      scid: d.nullable(scidReader),
      /** The same route resolution as the endpoint picker's. */
      failure: endpointFailure,
      /** U51: the revision its commands resolve to; null = unresolved (already a Catalog NO-GO). */
      catalog_revision: d.optional(d.nullable(revision)),
    }),
    1_000,
  ),
  checks: d.array(check, 20),
  /** U51: per command (by stack position), how each group of targets verifies it. */
  commands: d.optional(
    d.array(
      d.object({
        position: d.integer,
        command_id: d.token,
        verifier_groups: d.array(verifierGroupReader, 100),
        resolved_arguments: resolvedArgumentsReader,
      }),
      16,
    ),
  ),
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
/** commanding's own actor shape (`actor_kind` + `user_id`, not the shared entity actor). */
export const actor = d.object({
  actor_kind: d.knownText(["user", "system", "service"] as const),
  user_id: d.nullable(d.token),
});
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
  /** U68 (api d33d48f11): 0..9, lower sooner; null for very old groups. Optional until shipped. */
  priority: d.optional(d.nullable(d.integer)),
  expiry: expiryReader,
  // cfef9e9a: null unless state is queued. `finished` = every target final (not success).
  progress: d.optional(d.nullable(progressReader)),
  finished: d.optional(d.nullable(d.boolean)),
  /** U33: the pass this group is queued for and its readiness; null with no pass yet. */
  uplink: d.optional(d.nullable(groupUplinkReader)),
});
export type GroupRow = Decoded<typeof groupRow>;

export const groupsBase = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/command-groups`;

export function fetchPreflight(
  missionId: MissionId,
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
  missionId: MissionId,
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
  missionId: MissionId,
  draft: Draft,
  digest: string,
  operationId: string,
  acknowledgedHolds: readonly HoldAck[] = [],
  /** The Compose draft revision this came from: the server deletes that draft if still current. */
  draftRevision: number | null = null,
): Promise<WriteOutcome<Created>> {
  return outcomeOf(
    await request(groupsBase(missionId), created, {
      method: "POST",
      body: {
        ...draft,
        preflight_digest: digest,
        operation_id: operationId,
        acknowledged_holds: acknowledgedHolds,
        ...(draftRevision === null ? {} : { draft_revision: draftRevision }),
      },
    }),
  );
}

/** Compose's endpoint picker (commanding.md §GET /command-endpoints, DECISIONS #41). */
export const targetEndpointsReader = d.object({
  spacecraft_id: d.token,
  resolved_source_endpoint_id: d.nullable(d.token),
  failure: endpointFailure,
  routes: d.array(route, 100),
  endpoints: d.array(
    d.object({
      id: d.token,
      name: d.nullable(d.string),
      scid: d.nullable(scidReader),
      managed: d.boolean,
    }),
    50,
  ),
});
export type TargetEndpoints = Decoded<typeof targetEndpointsReader>;
const endpointList = d.object({ spacecraft: d.array(targetEndpointsReader, 1_000) });

export async function fetchEndpoints(
  missionId: MissionId,
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
