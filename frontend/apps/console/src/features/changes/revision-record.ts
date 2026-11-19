import { formatAbsolute, formatShort } from "@/ui";
import type { Actor, RevisionApproval, RevisionSummary } from "./shapes.ts";

/**
 * The four-eyes record in change history (U89; P3 #227). Tolerant until the dev reset: a revision
 * without `submitted_by` is the pre-P3 shape and keeps today's line, where `applied_by` is the
 * submitter on every path (P3 §2), so Submitted by falls back to it.
 * TIGHTEN (#227, with or after the dev reset): drop the pre-P3 branches.
 */

/** A name in a line, and whether it gets the ADMIN MODE tag after it. */
export type NamedActor = Readonly<{ name: string; adminMode: boolean }>;
/** A header is text with actor names between, so a name can carry its tag. */
export type HeaderPart = Readonly<{ text: string }> | Readonly<{ actor: NamedActor }>;

export type ApprovedBy =
  | Readonly<{ kind: "not_needed" }>
  | Readonly<{ kind: "approvers"; approvers: readonly NamedActor[] }>
  | Readonly<{ kind: "none" }>;

/** A known actor's name; "someone" when the server doesn't know it (a deleted user). */
export const who = (a: Actor | null | undefined): string =>
  a?.name ?? (a?.kind === "system" ? "Cadence" : "someone");

const named = (a: Actor | null | undefined, adminMode = false): NamedActor => ({
  name: who(a),
  adminMode,
});

/** Before P3 every entry was an approval, so an entry without `decision` (absent or null) is one. */
const isApproval = (a: RevisionApproval) =>
  a.decision === undefined || a.decision === null || a.decision === "approved";
const isNotRequired = (a: RevisionApproval) => a.decision === "not_required";

/** The Submitted by column: `submitted_by`, or `applied_by` on a pre-P3 row (the same person). */
export const submittedBy = (row: RevisionSummary): Actor | null =>
  row.submitted_by === undefined ? row.applied_by : row.submitted_by;

/** The Approved by column: the approvers, `Not needed` for not_required, or nothing. */
export function approvedBy(row: RevisionSummary): ApprovedBy {
  if (row.approvals.some(isNotRequired)) return { kind: "not_needed" };
  const approvers = row.approvals
    .filter(isApproval)
    .map((a) => named(a.actor, a.admin_mode === true));
  return approvers.length > 0 ? { kind: "approvers", approvers } : { kind: "none" };
}

/** Today's line: "Applied 2026-11-17 09:12:00Z by Mira K. · approved by Ana R." */
function appliedLine(row: RevisionSummary): readonly HeaderPart[] {
  const parts: HeaderPart[] = [{ text: `Applied ${formatAbsolute(new Date(row.applied_at))}` }];
  if (row.applied_by) parts.push({ text: " by " }, { actor: named(row.applied_by) });
  for (const a of row.approvals.filter(isApproval))
    parts.push({ text: " · approved by " }, { actor: named(a.actor, a.admin_mode === true) });
  return parts;
}

function joined(names: readonly NamedActor[]): readonly HeaderPart[] {
  return names.flatMap((actor, i): HeaderPart[] =>
    i === 0 ? [{ actor }] : [{ text: i === names.length - 1 ? " and " : ", " }, { actor }],
  );
}

/**
 * The revision header (U89): "Submitted by Mira K. · approved and applied by Ana R. · 11-17
 * 09:12Z"; "… · approved by Ana R. · applied by Owen P. · …" when they differ; "Submitted and
 * applied by Mira K. · 11-17 09:12Z · no second approval needed" when none was needed.
 */
export function revisionHeader(row: RevisionSummary): readonly HeaderPart[] {
  // A null actor drops its clause, as the table shows a dash; a nameless one reads "someone".
  if (!row.submitted_by) return appliedLine(row);
  const at = formatShort(new Date(row.applied_at));
  const approval = approvedBy(row);
  if (approval.kind === "not_needed")
    return [
      { text: "Submitted and applied by " },
      { actor: named(row.submitted_by) },
      { text: ` · ${at} · no second approval needed` },
    ];
  if (approval.kind === "none") return appliedLine(row);
  const approvers = row.approvals.filter(isApproval);
  const only = approvers.length === 1 ? approvers[0] : undefined;
  const appliedByApprover =
    only !== undefined &&
    only.actor.id !== null &&
    row.applied_by !== null &&
    only.actor.id === row.applied_by.id;
  return [
    { text: "Submitted by " },
    { actor: named(row.submitted_by) },
    { text: appliedByApprover ? " · approved and applied by " : " · approved by " },
    ...joined(approval.approvers),
    ...(appliedByApprover || !row.applied_by
      ? []
      : [{ text: " · applied by " }, { actor: named(row.applied_by) }]),
    { text: ` · ${at}` },
  ];
}
