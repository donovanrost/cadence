import { plural } from "@/ui";
import type { Group, MemberStage } from "../groups/show.ts";
import { NEEDS_YOU, type PersonName } from "../groups/words.ts";

/**
 * Uplink & verify (CommandFlow C3) in v1: the per-target trail from the group read. Only Verify
 * is green; commands without a verifier read "not verifiable", never green.
 */
const NOT_STARTED: readonly MemberStage[] = ["awaiting_go", "queued_for_contact"];

export type Pipeline = Readonly<{
  key: string;
  label: string;
  value: number;
  state: "nominal" | "crit" | "caution" | "stale" | undefined;
}>;

export function pipeline(group: Group): Pipeline[] {
  const n = (s: MemberStage) => group.progress[s] ?? 0;
  return [
    { key: "queued", label: "Queued for AOS", value: n("queued_for_contact"), state: undefined },
    { key: "radiating", label: "Radiating", value: n("radiating"), state: undefined },
    { key: "executed", label: "Executed", value: n("executed"), state: undefined },
    { key: "verified", label: "Verified", value: n("verified"), state: "nominal" },
    { key: "unverifiable", label: "Not verifiable", value: n("no_verifier"), state: "stale" },
    {
      key: "needs",
      label: "Need you",
      value: NEEDS_YOU.reduce((sum, s) => sum + n(s), 0),
      state: "crit",
    },
  ];
}

/** h1: `34 of 96 verified · 2 need you`; unverifiable stacks say executed, never verified. */
export function headline(group: Group, nameOf: PersonName): string {
  const total = group.target_count;
  const n = (s: MemberStage) => group.progress[s] ?? 0;
  const needs = NEEDS_YOU.reduce((sum, s) => sum + n(s), 0);
  const tail = needs ? ` · ${needs} need you` : "";
  if (group.state === "approval_pending")
    return `Waiting for a second GO · ${plural(total, "target")}`;
  // A closed request says how it closed, not "0 of N verified" (qa matrix nit 1).
  const by = nameOf(group.decided_by?.user_id ?? null);
  if (group.state === "rejected") return `Rejected by ${by} · nothing radiated`;
  if (group.state === "sent_back") return `Sent back by ${by} · edit and resend`;
  const started =
    total -
    n("canceled") -
    n("rejected") -
    n("excluded") -
    n("queued_for_contact") -
    n("awaiting_go");
  if (group.state === "aborted")
    return started > 0
      ? `Aborted · ${n("verified")} of ${started} started verified`
      : "Aborted · nothing radiated";
  if (n("no_verifier") === total) return `${total} executed · not verifiable`;
  return `${n("verified")} of ${total} verified${tail}`;
}

/** A target's stage when an earlier member is out but a later one may still wait. */
const UNDER_WAY: readonly MemberStage[] = ["radiating", "executed", "indeterminate"];

/**
 * Abort is offered while some uplink hasn't started to radiate (#795: from `progress`, the
 * server's count of every target by stage, not the targets on screen). A target's stage is its
 * first unfinished member's, so one under way still has later uplinks waiting when the request
 * stacks more than one command.
 */
export function abortable(group: Group): boolean {
  if (group.state !== "queued" && group.state !== "approval_pending") return false;
  const any = (stages: readonly MemberStage[]) => stages.some((s) => (group.progress[s] ?? 0) > 0);
  return any(NOT_STARTED) || (group.command_count > 1 && any(UNDER_WAY));
}
