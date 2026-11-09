import { plural, type OpState } from "@/ui";
import type { GroupState, MemberStage } from "./api.ts";
import type { GroupEvent } from "./show.ts";

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
export function memberStageWord(stage: MemberStage, group: GroupState): string {
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

/** Stages a target can't leave. */
export const FINAL_STAGES: readonly MemberStage[] = [
  "verified",
  "no_verifier",
  "verify_failed",
  "release_failed",
  "indeterminate",
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

/** One request-log line: what happened, by whom, with the note when there is one. */
export function eventText(e: GroupEvent, nameOf: PersonName): string {
  const who = nameOf(e.actor?.user_id ?? null);
  const p = e.payload;
  const note = p?.note ? `: “${p.note}”` : "";
  switch (e.kind) {
    case "submitted":
      return p?.members === undefined
        ? `${who} submitted it`
        : `${who} submitted ${plural(p.members, "uplink")}`;
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
    case "member_canceled":
      return `${who} canceled one uplink${p?.reason ? `: “${p.reason}”` : ""}`;
    default:
      return `${who} · ${e.kind.replaceAll("_", " ")}`;
  }
}
