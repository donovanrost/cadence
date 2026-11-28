import { MAX_TARGETS } from "./bounds.ts";
import type { MissionId } from "@/api/index.ts";
import { expiryReader } from "./expiryReader.ts";
import { resolvedArgumentsReader } from "./resolved.ts";
import {
  scid as scidReader,
  decoders as d,
  DecodeError,
  request,
  type ApiResult,
  type Decoded,
  type Reader,
  isKnown,
  type Unrecognized,
} from "@/api/index.ts";
import { groupUplinkReader } from "@/features/contacts/readiness.ts";
import { groupWithdrawnAfterGoReader, withdrawnAfterGoReader } from "./withdrawn.ts";
import { catalogRevisionReader, significance } from "../api.ts";
import { raw, releaseCode, releaseRefusalReader } from "./release.ts";
import {
  actor,
  groupsBase,
  memberStage as stage,
  progressReader as progress,
  groupStates,
  outcomeOf,
  preflightReader,
  type HoldAck,
  type Preflight,
  type WriteOutcome,
  verifierGroupReader,
} from "./api.ts";

/** One group (commanding.md §GET /command-groups/:id): Approve and Uplink & verify read this. */

export { memberStages, type MemberStage } from "./api.ts";

export const decisionKinds = ["go", "go_excluding", "send_back", "no_go"] as const;
/** commanding.md: why a member ended without radiating (or null). */
export const endReasons = [
  "aborted",
  "release_basis_changed",
  "earlier_command_failed",
  "expired",
  "catalog_changed",
  // L22 (api, ux U40): released never; the spacecraft was archived after preview.
  "spacecraft_archived",
  // E2 (#546, #1019): an unattended release refused it; the model's approval was withdrawn after GO.
  "model_approval_withdrawn_after_go",
  "excluded_at_review",
  "canceled",
  "rejected",
] as const;
/** Group request-log event kinds the log words; an unknown kind keeps the server's word. */
export const eventKinds = [
  "submitted",
  "approved",
  "approved_with_exclusions",
  "sent_back",
  "rejected",
  "note",
  "aborted",
  "hold_acknowledged",
  "member_canceled",
  "member_failed",
  "completed",
  // U46 (api): an operator released armed groups into a named contact.
  "released_on_contact",
  // U75 (api be3fa592b): once per request, at its expires_at, when members ended expired.
  "expired",
] as const;
export type EventKind = (typeof eventKinds)[number];

/** #795: why a failed member failed, from the same fact its member_failed event states. */
export const failureReasons = ["release_failed", "verify_failed", "verify_timed_out"] as const;

const member = d.object({
  position: d.integer,
  target_index: d.integer,
  request_id: d.token,
  command_id: d.token,
  command_name: d.nullable(d.string),
  stage,
  end_reason: d.nullable(d.knownText(endReasons)),
  failure_reason: d.nullable(d.knownText(failureReasons)),
  verify_by: d.nullable(d.timestamp),
  /** api 3438b783c: when it verified, timed out or failed (null when it doesn't apply). */
  verified_at: d.optional(d.nullable(d.timestamp)),
  timed_out_at: d.optional(d.nullable(d.timestamp)),
  failed_at: d.optional(d.nullable(d.timestamp)),
  occurred_at: d.nullable(d.timestamp),
  /** U46: its latest named-release stop; a window-closed stop leaves it queued. */
  release_refusal: d.optional(d.nullable(releaseRefusalReader)),
});
export type GroupMember = Decoded<typeof member>;

export const targetReader = d.object({
  /** #795: its place in the group's target order (what the targets read pages by). */
  index: d.integer,
  spacecraft_id: d.token,
  name: d.nullable(d.string),
  scid: d.nullable(scidReader),
  stage,
  members: d.array(member, 16),
  last_event_at: d.nullable(d.timestamp),
  /** E2 (#1042): its craft's model approval was withdrawn after the GO its waiting uplinks had. */
  withdrawn_after_go: d.nullable(withdrawnAfterGoReader),
  /** Waiting on its contact behind a release whose outcome is unknown: "Needs you" shows it. */
  blocked: d.optional(
    d.nullable(
      d.object({
        reason: d.knownText(["lane_release_uncertain"] as const),
        command_request_id: d.optional(d.token),
      }),
    ),
  ),
});
export type GroupTarget = Decoded<typeof targetReader>;

const command = d.object({
  position: d.integer,
  command_id: d.token,
  name: d.nullable(d.string),
  significance,
  critical: d.boolean,
  hazardous: d.boolean,
  argument_values_json: d.string,
  /** U51 (api): how each group of targets verifies it, from each member's pinned revision. */
  verifier_groups: d.optional(d.array(verifierGroupReader, 100)),
  /** U68 R1: where the server's value differs from what was entered. */
  resolved_arguments: resolvedArgumentsReader,
  // api f1bed1880: each target's own values ([] when none); optional for older reads.
  per_target: d.optional(
    d.array(d.object({ spacecraft_id: d.token, argument_values_json: d.string }), MAX_TARGETS),
  ),
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

/** #51 failure reasons and `completed` outcome keys (commanding.md; L22 adds spacecraft_archived). */
export const outcomeKeys = [
  "verified",
  "no_verifier",
  "verify_failed",
  "verify_timed_out",
  "catalog_changed",
  "release_failed",
  "spacecraft_archived",
  "canceled",
  "rejected",
] as const;
export type OutcomeKey = (typeof outcomeKeys)[number];
/** A log reason as text: member_failed's key, or an operator's abort / cancel sentence as said. */
export const reasonText = (reason: OutcomeKey | Unrecognized): string =>
  isKnown(reason) ? reason : reason.unrecognized;

export const eventReader = d.object({
  id: d.token,
  kind: d.knownText(eventKinds),
  actor: d.nullable(eventActor),
  at: d.timestamp,
  payload: d.nullable(
    d.object({
      note: d.optional(d.nullable(d.string)),
      // One field, two meanings as the log sends it: member_failed's reason key (worded in
      // words.ts) or an operator's abort / cancel sentence, which arrives unrecognized, as said.
      reason: d.optional(d.nullable(d.knownText(outcomeKeys))),
      members: d.optional(eventMembers),
      approved: d.optional(d.integer),
      excluded: d.optional(d.array(d.token, MAX_TARGETS)),
      /** A count; `already_started` lists the request ids that kept running. */
      canceled: d.optional(d.integer),
      already_started: d.optional(d.array(d.token, 5_000)),
      command_request_id: d.optional(d.token),
      // hold_acknowledged (#60)
      key: d.optional(d.token),
      hold_basis: d.optional(d.nullable(d.string)),
      at_decision: d.optional(d.boolean),
      // #546 (ca-engineer): the HOLD's evidence as acknowledged; the Composition check names its targets.
      evidence: d.optional(
        d.nullable(d.object({ spacecraft_ids: d.optional(d.array(d.token, MAX_TARGETS)) })),
      ),
      // expired (U75): how many went out, and how many it ended.
      sent: d.optional(d.integer),
      not_sent: d.optional(d.integer),
      // member_failed (#51)
      spacecraft_id: d.optional(d.token),
      position: d.optional(d.integer),
      later_members_stopped: d.optional(d.integer),
      // released_on_contact (U46)
      booked: d.optional(d.boolean),
      released_entry_ids: d.optional(d.array(d.token, 1_000)),
      not_attempted_entry_ids: d.optional(d.array(d.token, 1_000)),
      realized_contact_id: d.optional(d.token),
      stopped: d.optional(
        d.nullable(
          d.object({
            command_queue_entry_id: d.token,
            reason: d.optional(d.object({ code: releaseCode, details: d.optional(raw) })),
          }),
        ),
      ),
    }),
  ),
});
export type GroupEvent = Decoded<typeof eventReader>;

/** #795: how many targets there are and a revision that moves with any target's stage. */
const targetsPage = d.object({
  total: d.integer,
  revision: d.integer,
  next_cursor: d.nullable(d.string),
});
/** #795: how many events there are; a push carrying a new total means new events. */
const eventsPage = d.object({ total: d.integer, next_cursor: d.nullable(d.string) });

/** Everything a group read and its push both carry (the push has no targets or events, #795). */
const groupShape = {
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
  /** The members' catalog revision ("Catalog rev 14"), null when none records it. */
  catalog_revision: catalogRevisionReader,
  log_entry: d.nullable(d.string),
  sent_back_from: d.nullable(d.token),
  commands: d.array(command, 16),
  /** U75: set once any member ended expired. */
  expiry: expiryReader,
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
      kind: d.knownText(decisionKinds),
      // The size guard's max_targets (5,000) bounds it; the server validates each id.
      excluded: d.optional(d.array(d.token, MAX_TARGETS)),
      note: d.nullable(d.string),
    }),
  ),
  decided_by: d.nullable(actor),
  decided_at: d.nullable(d.timestamp),
  aborted_by: d.nullable(actor),
  aborted_at: d.nullable(d.timestamp),
  // free-text: the operator's own sentence
  abort_reason: d.nullable(d.string),
  /** E2 (#1042): the targets flagged across the whole group, and the newest decision; null with none. */
  withdrawn_after_go: groupWithdrawnAfterGoReader,
  progress,
  finished: d.optional(d.boolean),
  uplink: d.optional(d.nullable(groupUplinkReader)),
  targets_page: targetsPage,
  events_page: eventsPage,
};

/**
 * The group read (#795): the first targets (at most 100, in target order) and the latest events
 * (at most 50, oldest first), with their pages' totals; `groups/pages.ts` reads the rest.
 */
export const groupReader = d.object({
  ...groupShape,
  targets: d.array(targetReader, 500),
  events: d.array(eventReader, 200),
});
export type Group = Decoded<typeof groupReader>;

/** The group channel's push: the same read without the targets and events (#795). */
export const groupPushReader = d.object(groupShape);
export type GroupPush = Decoded<typeof groupPushReader>;

const one = (missionId: MissionId, id: string) =>
  `${groupsBase(missionId)}/${encodeURIComponent(id)}`;

export function fetchGroup(
  missionId: MissionId,
  id: string,
  signal?: AbortSignal,
): Promise<ApiResult<Group>> {
  return request(one(missionId, id), groupReader, signal ? { signal } : {});
}

/** Preflight re-run at review (A2), with `changed_since_submit`. */
export function fetchReview(
  missionId: MissionId,
  id: string,
  signal?: AbortSignal,
): Promise<ApiResult<Preflight>> {
  return request(`${one(missionId, id)}/preflight`, preflightReader, signal ? { signal } : {});
}

export type DecisionKind = (typeof decisionKinds)[number];
export type Decision = Readonly<{
  kind: DecisionKind;
  excluded: readonly string[];
  note: string;
  expectedReview: string;
  /** #61: the approver's acks for HOLDs the author's acks don't cover (GO kinds only). */
  acknowledgedHolds?: readonly HoldAck[];
}>;

export async function decide(
  missionId: MissionId,
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
        acknowledged_holds: decision.acknowledgedHolds ?? [],
      },
    }),
  );
}

export async function abortGroup(
  missionId: MissionId,
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
