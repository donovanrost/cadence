import {
  decode,
  decoders as d,
  describeApiError,
  knownErrorCode,
  type ApiError,
  type ErrorCode,
} from "@/api/index.ts";
import { plural } from "@/ui";
import type { Preflight } from "../groups/api.ts";
import { checkLabel } from "../groups/checks.ts";
import type { DecisionKind, Group } from "../groups/show.ts";
import type { PersonName } from "../groups/words.ts";

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
      // ux §7 #13: the check's label as A2 shows it, never its key.
      return `The ${checkLabel(check.key)} re-check is NO-GO.`;
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
  // ux §7 #14: up to 3 names in the title; more read as a count, with the names below.
  const names = flagged.map((f) => f.name).join(", ");
  const many = flagged.length > 3;
  if (flagged.length && flagged.length < n)
    options.push({
      value: "go_excluding",
      title: many ? `GO, excluding ${flagged.length} flagged targets` : `GO, excluding ${names}`,
      description: `${many ? `Excludes ${names}. ` : ""}${plural(n - flagged.length, "target")}; the rest are rejected as excluded at review.`,
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

const ERROR_WORDS: Readonly<Partial<Record<ErrorCode, string>>> = {
  command_group_review_stale: "It changed while you reviewed it. It's been reloaded; review again.",
  command_group_basis_changed:
    "The active catalog changed since it was submitted. The author has to resubmit.",
  command_group_not_pending: "Someone already decided it.",
  command_group_self_approval_not_allowed: "You can't approve your own request.",
  not_the_requested_approver: "Another operator was asked for this GO.",
  holds_unacknowledged:
    "A HOLD isn't acknowledged against the latest checks. They've been re-run; read them and acknowledge again.",
};
/**
 * ux U92: GO refused because the group's commands changed after it was submitted. The whole line
 * replaces "Not recorded…"; the panel keeps it as GO's reason (A6), and NO-GO stays the way out.
 */
export function membersChangedLine(details: unknown): string {
  const c = decode(memberCounts, details);
  const counts =
    c.ok &&
    c.value.submitted_member_count !== undefined &&
    c.value.current_member_count !== undefined
      ? ` (${c.value.submitted_member_count} then, ${c.value.current_member_count} now)`
      : "";
  return `Not released: this group's commands changed after it was submitted${counts}, so it isn't what was reviewed. Give it NO-GO and submit the commands again. Tell the team that runs Cadence for you: a group shouldn't change after it's submitted.`;
}
/** U92 (api-ops): both counts, or the bracket goes. */
const memberCounts = d.object({
  submitted_member_count: d.optional(d.integer),
  current_member_count: d.optional(d.integer),
});

/** A refused decision in words: the code's sentence when the console has one, else the server's. */
export function decisionErrorWords(e: ApiError): string {
  const code = knownErrorCode(e);
  return (code && ERROR_WORDS[code]) ?? describeApiError(e);
}

/** §4 short: `03:10Z` today, `11-10 03:10Z` otherwise. */
function at(iso: string | null, now: Date): string {
  if (!iso) return "";
  const today = iso.slice(0, 10) === now.toISOString().slice(0, 10);
  return ` at ${today ? "" : `${iso.slice(5, 10)} `}${iso.slice(11, 16)}Z`;
}

/**
 * ux §7 #15: what was decided, by whom and when, with the note; null while it's still open.
 * "GO signed by Ana P. at 03:10Z", "Sent back by Ana P. at 03:10Z: “…”".
 */
export function decisionRecord(
  group: Group,
  nameOf: PersonName,
  now: Date = new Date(),
): Readonly<{ tone: "info" | "off"; text: string }> | null {
  if (group.state === "approval_pending") return null;
  if (group.state === "aborted")
    return {
      tone: "off",
      text: `Aborted by ${nameOf(group.aborted_by?.user_id ?? null)}${at(group.aborted_at, now)}${group.abort_reason ? `: “${group.abort_reason}”` : "."}`,
    };
  const d = group.decision;
  const who = nameOf(group.decided_by?.user_id ?? null);
  const when = at(group.decided_at, now);
  const note = d?.note ? `: “${d.note}”` : ".";
  if (!d)
    return group.state === "queued"
      ? { tone: "info", text: "No second GO was needed; it was released at submit." }
      : { tone: "off", text: "Decided; the record has no details." };
  switch (d.kind) {
    case "go":
      return { tone: "info", text: `GO signed by ${who}${when}${note}` };
    case "go_excluding": {
      const n = d.excluded?.length ?? 0;
      return {
        tone: "info",
        text: `GO signed by ${who}${when}, excluding ${plural(n, "target")}${note}`,
      };
    }
    case "send_back":
      return { tone: "off", text: `Sent back by ${who}${when}${note}` };
    case "no_go":
      return { tone: "off", text: `NO-GO signed by ${who}${when}${note}` };
    default:
      return { tone: "off", text: `Decided by ${who}${when}${note}` };
  }
}
