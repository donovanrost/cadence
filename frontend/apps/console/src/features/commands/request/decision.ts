import { plural } from "@/ui";
import type { Preflight } from "../groups/api.ts";
import type { DecisionKind, Group } from "../groups/show.ts";

/**
 * Approve D · Your call (CommandFlow C2). Options follow what the re-check found: `GO, excluding`
 * appears only when it flagged targets, and excludes exactly those. Whether you may decide at
 * all comes from the server (awaiting_me, command.approve); the console only explains it.
 */
export type Flagged = Readonly<{ spacecraftId: string; name: string }>;

/** Structurally an ApDecisionOption (declared here so plain TS sees the type, not the SFC). */
export type DecisionOption = Readonly<{
  value: DecisionKind;
  title: string;
  description?: string;
  needsNote?: boolean;
  commitLabel: string;
}>;

/**
 * Targets a re-check marked HOLD or NO-GO, i.e. candidates to exclude. The contact check doesn't
 * count: waiting for a booked pass is the normal release path, not a reason to drop a target.
 */
export function flaggedTargets(
  review: Preflight | null,
  nameOf: (spacecraftId: string) => string,
): Flagged[] {
  if (!review) return [];
  const ids = new Set<string>();
  for (const check of review.checks) {
    if (check.key === "contact" || check.key === "two_person") continue;
    for (const t of check.per_target) if (t.result !== "go") ids.add(t.spacecraft_id);
  }
  return [...ids].map((spacecraftId) => ({ spacecraftId, name: nameOf(spacecraftId) }));
}

/** A NO-GO at review blocks GO; excluding the flagged targets can clear it if each NO-GO is per-target. */
export function noGoAfter(review: Preflight | null, excluded: ReadonlySet<string>): string | null {
  if (!review) return "The re-check hasn't answered yet.";
  for (const check of review.checks) {
    if (check.result !== "no_go") continue;
    const left = check.per_target.filter(
      (t) => t.result === "no_go" && !excluded.has(t.spacecraft_id),
    );
    if (check.per_target.length === 0 || left.length > 0)
      return `The ${check.key.replaceAll("_", " ")} re-check is NO-GO.`;
  }
  return null;
}

export function decisionOptions(group: Group, flagged: readonly Flagged[]): DecisionOption[] {
  const n = group.target_count;
  const options: DecisionOption[] = [
    {
      value: "go",
      title: "GO as requested",
      description: `${plural(n, "target")} · ${plural(group.member_count, "uplink")}`,
      commitLabel: `Sign GO · ${plural(n, "target")}`,
    },
  ];
  if (flagged.length && flagged.length < n)
    options.push({
      value: "go_excluding",
      title: `GO, excluding ${flagged.map((f) => f.name).join(", ")}`,
      description: `${plural(n - flagged.length, "target")}; the rest are rejected as excluded at review.`,
      needsNote: true,
      commitLabel: `Sign GO · ${plural(n - flagged.length, "target")}`,
    });
  options.push(
    {
      value: "send_back",
      title: "Send back",
      description: "Returns it to the author with your note.",
      needsNote: true,
      commitLabel: "Send back",
    },
    {
      value: "no_go",
      title: "NO-GO",
      description: "Closes the request and logs why.",
      needsNote: true,
      commitLabel: "Sign NO-GO",
    },
  );
  return options;
}

/** Why the viewer can't decide, in words; null when they can. */
export function cannotDecide(
  group: Group,
  viewerId: string,
  canApprove: boolean,
  nameOf: (userId: string | null) => string,
): string | null {
  if (group.state !== "approval_pending") return "This request isn't waiting for a GO.";
  if (group.requested_by.user_id === viewerId)
    return `You can't approve your own request. Waiting on ${group.requested_approver_user_id ? nameOf(group.requested_approver_user_id) : "another operator with command approval"}.`;
  if (!canApprove) return "Giving a GO needs command approval in this organization.";
  if (!group.awaiting_me)
    return `${nameOf(group.requested_approver_user_id)} was asked for this GO.`;
  return null;
}

const ERROR_WORDS: Readonly<Record<string, string>> = {
  command_group_review_stale: "It changed while you reviewed it. It's been reloaded; review again.",
  command_group_basis_changed:
    "The active catalog changed since it was submitted. The author has to resubmit.",
  command_group_not_pending: "Someone already decided it.",
  command_group_self_approval_not_allowed: "You can't approve your own request.",
  not_the_requested_approver: "Another operator was asked for this GO.",
  holds_unacknowledged:
    "A HOLD isn't acknowledged against the latest checks. They've been re-run; read them and acknowledge again.",
};
export const decisionErrorWords = (code: string, message: string) => ERROR_WORDS[code] ?? message;
