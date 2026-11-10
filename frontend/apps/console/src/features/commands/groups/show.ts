import {
  decoders as d,
  DecodeError,
  request,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api/index.ts";
import { groupUplinkReader } from "@/features/contacts/readiness.ts";
import {
  actor,
  groupsBase,
  memberStage as stage,
  progressReader as progress,
  groupStates,
  outcomeOf,
  preflightReader,
  type Preflight,
  type WriteOutcome,
} from "./api.ts";

/** One group (commanding.md §GET /command-groups/:id): Approve and Uplink & verify read this. */

export { memberStages, type MemberStage } from "./api.ts";

const member = d.object({
  position: d.integer,
  target_index: d.integer,
  request_id: d.token,
  command_id: d.token,
  command_name: d.nullable(d.string),
  stage,
  end_reason: d.nullable(d.token),
  verify_by: d.nullable(d.timestamp),
  occurred_at: d.nullable(d.timestamp),
});
export type GroupMember = Decoded<typeof member>;

const target = d.object({
  spacecraft_id: d.token,
  name: d.nullable(d.string),
  scid: d.nullable(d.integer),
  stage,
  members: d.array(member, 16),
  last_event_at: d.nullable(d.timestamp),
});
export type GroupTarget = Decoded<typeof target>;

const command = d.object({
  position: d.integer,
  command_id: d.token,
  name: d.nullable(d.string),
  significance: d.nullable(d.token),
  critical: d.boolean,
  hazardous: d.boolean,
  argument_values_json: d.string,
});
export type GroupCommand = Decoded<typeof command>;

const reason = d.object({
  key: d.token,
  command_id: d.optional(d.token),
  name: d.optional(d.string),
  targets: d.optional(d.integer),
  threshold: d.optional(d.integer),
});

/** `submitted` counts uplinks; `completed` (#51) tallies final outcomes `{verified: 3, …}`. */
const eventMembers: Reader<number | Readonly<Record<string, number>>> = (value, path = "") => {
  if (typeof value === "number") return d.integer(value, path);
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new DecodeError(path, "integer or object");
  const out: Record<string, number> = {};
  for (const [key, count] of Object.entries(value))
    out[d.token(key, `${path}.${key}`)] = d.integer(count, `${path}.${key}`);
  return out;
};

/**
 * An event's actor (commanding.md §Timeline events): a person `{actor_kind: "user", user_id}`, or
 * `{actor_kind: "system"}` with no user for #51 member_failed/completed. The log names the
 * system "Cadence".
 */
const eventActor = d.variant("actor_kind", {
  user: d.object({ actor_kind: d.oneOf(["user"] as const), user_id: d.token }),
  system: d.object({ actor_kind: d.oneOf(["system"] as const) }),
});

const event = d.object({
  id: d.token,
  kind: d.token,
  actor: d.nullable(eventActor),
  at: d.timestamp,
  payload: d.nullable(
    d.object({
      note: d.optional(d.nullable(d.string)),
      reason: d.optional(d.nullable(d.string)),
      members: d.optional(eventMembers),
      approved: d.optional(d.integer),
      excluded: d.optional(d.array(d.token, 1_000)),
      /** A count; `already_started` lists the request ids that kept running. */
      canceled: d.optional(d.integer),
      already_started: d.optional(d.array(d.token, 5_000)),
      command_request_id: d.optional(d.token),
      // hold_acknowledged (#60)
      key: d.optional(d.token),
      // member_failed (#51)
      spacecraft_id: d.optional(d.token),
      position: d.optional(d.integer),
      later_members_stopped: d.optional(d.integer),
    }),
  ),
});
export type GroupEvent = Decoded<typeof event>;

export const groupReader = d.object({
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
  review_token: d.string,
  log_entry: d.nullable(d.string),
  sent_back_from: d.nullable(d.token),
  commands: d.array(command, 16),
  release: d.nullable(
    d.object({
      not_before: d.nullable(d.timestamp),
      expires_at: d.nullable(d.timestamp),
      priority: d.nullable(d.integer),
    }),
  ),
  policy: d.nullable(
    d.object({ second_go_required: d.boolean, reasons: d.optional(d.array(reason, 100)) }),
  ),
  decision: d.nullable(
    d.object({
      kind: d.token,
      excluded: d.optional(d.array(d.token, 1_000)),
      note: d.nullable(d.string),
    }),
  ),
  decided_by: d.nullable(actor),
  decided_at: d.nullable(d.timestamp),
  aborted_by: d.nullable(actor),
  aborted_at: d.nullable(d.timestamp),
  abort_reason: d.nullable(d.string),
  targets: d.array(target, 1_000),
  progress,
  finished: d.optional(d.boolean),
  uplink: d.optional(d.nullable(groupUplinkReader)),
  events: d.array(event, 10_000),
});
export type Group = Decoded<typeof groupReader>;

const one = (missionId: string, id: string) => `${groupsBase(missionId)}/${encodeURIComponent(id)}`;

export function fetchGroup(
  missionId: string,
  id: string,
  signal?: AbortSignal,
): Promise<ApiResult<Group>> {
  return request(one(missionId, id), groupReader, signal ? { signal } : {});
}

/** Preflight re-run at review (A2), with `changed_since_submit`. */
export function fetchReview(
  missionId: string,
  id: string,
  signal?: AbortSignal,
): Promise<ApiResult<Preflight>> {
  return request(`${one(missionId, id)}/preflight`, preflightReader, signal ? { signal } : {});
}

export type DecisionKind = "go" | "go_excluding" | "send_back" | "no_go";
export type Decision = Readonly<{
  kind: DecisionKind;
  excluded: readonly string[];
  note: string;
  expectedReview: string;
}>;

export async function decide(
  missionId: string,
  id: string,
  decision: Decision,
): Promise<WriteOutcome<Group>> {
  return outcomeOf(
    await request(`${one(missionId, id)}/decision`, groupReader, {
      method: "POST",
      body: {
        kind: decision.kind,
        excluded: decision.excluded,
        note: decision.note,
        expected_review: decision.expectedReview,
      },
    }),
  );
}

export async function abortGroup(
  missionId: string,
  id: string,
  reason: string,
): Promise<WriteOutcome<Group>> {
  return outcomeOf(
    await request(`${one(missionId, id)}/abort`, groupReader, {
      method: "POST",
      body: { reason },
    }),
  );
}
