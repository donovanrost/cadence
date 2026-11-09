import { plural } from "@/ui";
import type { Group, MemberStage } from "../groups/show.ts";

/**
 * Uplink & verify (CommandFlow C3) in v1: the per-target trail from the group read. Only Verify
 * is green; commands without a verifier read "not verifiable", never green.
 */
export const NEEDS_YOU: readonly MemberStage[] = [
  "verify_failed",
  "release_failed",
  "indeterminate",
];
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
export function headline(group: Group): string {
  const total = group.target_count;
  const n = (s: MemberStage) => group.progress[s] ?? 0;
  const needs = NEEDS_YOU.reduce((sum, s) => sum + n(s), 0);
  const tail = needs ? ` · ${needs} need you` : "";
  if (group.state === "approval_pending")
    return `Waiting for a second GO · ${plural(total, "target")}`;
  if (n("no_verifier") === total) return `${total} executed · not verifiable`;
  return `${n("verified")} of ${total} verified${tail}`;
}

/** Abort is offered while some uplink hasn't started to radiate. */
export const abortable = (group: Group) =>
  (group.state === "queued" || group.state === "approval_pending") &&
  group.targets.some((t) => t.members.some((m) => NOT_STARTED.includes(m.stage)));
