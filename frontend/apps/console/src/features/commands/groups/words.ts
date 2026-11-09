import { plural, type OpState } from "@/ui";
import type { GroupState } from "./api.ts";
import type { GroupEvent, MemberStage } from "./show.ts";

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
