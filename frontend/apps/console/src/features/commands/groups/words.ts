import { isKnown } from "@/api/index.ts";
import { plural, type OpState } from "@/ui";
import type { GroupState, MemberStage } from "./api.ts";
import { checkLabel } from "./checks.ts";
import type { GroupEvent, GroupMember } from "./show.ts";

/**
 * Words for command groups (CommandFlow: "sent is not done"; only Verify turns green). Progress
 * stages stay gray; outcomes carry status.
 */
export const STAGE_WORDS: Readonly<Record<MemberStage, string>> = {
  awaiting_go: "Awaiting GO",
  queued_for_contact: "Queued for AOS",
  radiating: "Radiating",
  executed: "Executed",
  verified: "Verified",
  no_verifier: "Executed · not verifiable",
  verify_failed: "Verify failed",
  release_failed: "Release failed",
  indeterminate: "Outcome unclear",
  canceled: "Canceled",
  rejected: "Rejected",
  excluded: "Excluded",
};

export const STAGE_STATE: Readonly<Record<MemberStage, OpState>> = {
  awaiting_go: "neutral",
  queued_for_contact: "neutral",
  radiating: "live",
  executed: "neutral",
  verified: "nominal",
  no_verifier: "stale",
  verify_failed: "crit",
  release_failed: "crit",
  indeterminate: "caution",
  canceled: "off",
  rejected: "off",
  excluded: "off",
};

/** A member's stage in words, in its group's terms: a sent-back member wasn't rejected. */
export function memberStageWord(
  stage: MemberStage,
  group: GroupState,
  endReason: GroupMember["end_reason"] = null,
): string {
  // #65: a catalog change set canceled it before release.
  if (stage === "canceled" && endReason === "catalog_changed")
    return "Canceled: the catalog changed";
  if (stage === "rejected" && group === "sent_back") return "Sent back";
  if (stage === "rejected" && group === "rejected") return "NO-GO";
  return STAGE_WORDS[stage];
}

export const GROUP_STATE_WORDS: Readonly<Record<GroupState, string>> = {
  approval_pending: "Waiting for a second GO",
  queued: "GO given · released to the queue",
  rejected: "NO-GO",
  sent_back: "Sent back",
  aborted: "Aborted",
};

export const GROUP_STATE: Readonly<Record<GroupState, OpState>> = {
  approval_pending: "caution",
  queued: "neutral",
  rejected: "off",
  sent_back: "off",
  aborted: "off",
};

/** `{stage: target count}`, from the show read or a list row. */
export type Progress = Readonly<Partial<Record<MemberStage, number>>>;

/** Stages a target can't leave (b5d6ed6d: `indeterminate` waits on an operator, so it isn't). */
export const FINAL_STAGES: readonly MemberStage[] = [
  "verified",
  "no_verifier",
  "verify_failed",
  "release_failed",
  "canceled",
  "rejected",
  "excluded",
];
/** Reached the spacecraft (verify outcome aside). */
const DELIVERED: readonly MemberStage[] = ["executed", "verified", "no_verifier", "verify_failed"];
export const NEEDS_YOU: readonly MemberStage[] = [
  "verify_failed",
  "release_failed",
  "indeterminate",
];

const count = (p: Progress, stages: readonly MemberStage[]) =>
  stages.reduce((sum, s) => sum + (p[s] ?? 0), 0);

/** A released request whose every target is final (the run is over; not "succeeded"). */
export const finished = (state: GroupState, p: Progress | null | undefined, targets: number) =>
  state === "queued" && p != null && targets > 0 && count(p, FINAL_STAGES) >= targets;

/**
 * A request's status tag. After GO the approval state stays `queued` for good (commanding.md:
 * delivery lives in progress), so a released request reads its delivery, never just "queued".
 * Without progress it says only what's certain: GO was given.
 */
export function statusTag(
  state: GroupState,
  p: Progress | null | undefined,
  targets: number,
): Readonly<{ label: string; state: OpState }> {
  if (state !== "queued") return { label: GROUP_STATE_WORDS[state], state: GROUP_STATE[state] };
  if (p == null) return { label: "GO given", state: "neutral" };
  const final = count(p, FINAL_STAGES);
  const started = count(p, DELIVERED) + count(p, ["radiating", "release_failed", "indeterminate"]);
  if (started === 0 && final === 0) return { label: GROUP_STATE_WORDS.queued, state: "neutral" };
  const needs = count(p, NEEDS_YOU);
  const label = `${count(p, DELIVERED)}/${targets} delivered${needs ? ` · ${needs} need you` : ""}`;
  if (needs) return { label, state: "crit" };
  if (final >= targets) return { label, state: (p.verified ?? 0) >= targets ? "nominal" : "stale" };
  return { label, state: p.radiating ? "live" : "neutral" };
}

export type PersonName = (userId: string | null) => string;

/** #51 failure reasons and `completed` outcome keys, in operator words. */
const OUTCOME_WORDS: Readonly<Record<string, string>> = {
  verified: "verified",
  no_verifier: "not verifiable",
  verify_failed: "verify failed",
  verify_timed_out: "verify timed out",
  catalog_changed: "canceled by a catalog change",
  release_failed: "release failed",
  canceled: "canceled",
  rejected: "rejected",
};
const outcomeWord = (key: string) => OUTCOME_WORDS[key] ?? key.replaceAll("_", " ");

/** Enough of a group to name a failed member: `SET_MODE on EARENDIL-004`. */
export type EventTargets = readonly Readonly<{
  spacecraft_id: string;
  name: string | null;
  members: readonly Readonly<{ position: number; command_name: string | null }>[];
}>[];

function memberName(e: GroupEvent, targets: EventTargets): string {
  const p = e.payload;
  const t = targets.find((x) => x.spacecraft_id === p?.spacecraft_id);
  const cmd = t?.members.find((m) => m.position === p?.position)?.command_name;
  const sc = t?.name ?? p?.spacecraft_id;
  return cmd && sc ? `${cmd} on ${sc}` : sc ? `An uplink to ${sc}` : "An uplink";
}

/** Log lines that need someone carry status; the rest stay gray. */
export const eventState = (e: GroupEvent): OpState =>
  e.kind === "member_failed" ? "crit" : "neutral";

/** One request-log line: what happened, by whom, with the note when there is one. */
export function eventText(e: GroupEvent, nameOf: PersonName, targets: EventTargets = []): string {
  // A system actor has no user; nameOf(null) is "Cadence".
  const who = nameOf(e.actor?.actor_kind === "user" ? e.actor.user_id : null);
  const p = e.payload;
  const note = p?.note ? `: “${p.note}”` : "";
  switch (e.kind) {
    case "submitted":
      return typeof p?.members === "number"
        ? `${who} submitted ${plural(p.members, "uplink")}`
        : `${who} submitted it`;
    case "approved":
      return `${who} gave GO${note}`;
    case "approved_with_exclusions":
      return `${who} gave GO, excluding ${p?.excluded?.length ?? "some"} targets${note}`;
    case "sent_back":
      return `${who} sent it back${note}`;
    case "rejected":
      return `${who} gave NO-GO${note}`;
    case "note":
      return `${who} noted${note}`;
    case "aborted":
      return `${who} aborted${p?.reason ? `: “${p.reason}”` : ""} · ${p?.canceled ?? 0} canceled, ${p?.already_started?.length ?? 0} already started`;
    case "hold_acknowledged":
      return `${who} acknowledged the ${p?.key ? checkLabel(p.key) : "a"} HOLD${p?.at_decision ? " at GO" : ""}${note}`;
    case "member_canceled":
      return `${who} canceled one uplink${p?.reason ? `: “${p.reason}”` : ""}`;
    case "member_failed": {
      const stopped = p?.later_members_stopped ?? 0;
      return `${who}: ${memberName(e, targets)} ${outcomeWord(p?.reason ?? "failed")}${stopped ? ` · ${plural(stopped, "later uplink")} stopped` : ""}`;
    }
    case "completed": {
      const m = p?.members;
      const tally =
        typeof m === "object" ? Object.entries(m).map(([k, n]) => `${n} ${outcomeWord(k)}`) : [];
      return [`${who} closed the run`, ...tally].join(" · ");
    }
    default:
      return `${who} · ${(isKnown(e.kind) ? e.kind : e.kind.unrecognized).replaceAll("_", " ")}`;
  }
}
