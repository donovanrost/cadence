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

/**
 * An actor's name in a line (U25, #308): a person by name; Cadence itself as "Cadence"; a service
 * identity as "Nightly planner (a service identity)", or "a service identity" with no name (U103,
 * #371). A person with no name is null: their name drops, and the act and the time stay.
 */
export function who(a: Actor | null | undefined): string | null {
  if (!a) return null;
  if (a.kind === "system") return a.name ?? "Cadence";
  if (a.kind === "service") return a.name ? `${a.name} (a service identity)` : "a service identity";
  return a.name;
}

/** A name for a line; a nameless actor in admin mode keeps only its tag (it follows the verb). */
const named = (a: Actor | null | undefined, adminMode = false): NamedActor | null => {
  const name = who(a);
  if (name !== null) return { name, adminMode };
  return adminMode ? { name: "", adminMode } : null;
};

/** Before P3 every entry was an approval, so an entry without `decision` (absent or null) is one. */
const isApproval = (a: RevisionApproval) =>
  a.decision === undefined || a.decision === null || a.decision === "approved";
const isNotRequired = (a: RevisionApproval) => a.decision === "not_required";

/** The Submitted by column: `submitted_by`, or `applied_by` on a pre-P3 row (the same person). */
export const submittedBy = (row: RevisionSummary): Actor | null =>
  row.submitted_by === undefined ? row.applied_by : row.submitted_by;

/**
 * The Approved by column: the approvers who can be named (a nameless one drops, #308),
 * `Not needed` for not_required, or nothing.
 */
export function approvedBy(row: RevisionSummary): ApprovedBy {
  if (row.approvals.some(isNotRequired)) return { kind: "not_needed" };
  const approvals = row.approvals.filter(isApproval);
  if (approvals.length === 0) return { kind: "none" };
  const approvers = approvals.flatMap((a) => named(a.actor, a.admin_mode === true) ?? []);
  return { kind: "approvers", approvers };
}

/** " by Mira K.", " by" + the tag alone, or nothing for a nameless person (U25, #308). */
const byClause = (actor: NamedActor | null): readonly HeaderPart[] =>
  actor === null ? [] : actor.name ? [{ text: " by " }, { actor }] : [{ actor }];

/** Today's line: "Applied 2026-11-17 09:12:00Z by Mira K. · approved by Ana R." */
function appliedLine(row: RevisionSummary): readonly HeaderPart[] {
  const parts: HeaderPart[] = [{ text: `Applied ${formatAbsolute(new Date(row.applied_at))}` }];
  parts.push(...byClause(named(row.applied_by)));
  for (const a of row.approvals.filter(isApproval))
    parts.push({ text: " · approved" }, ...byClause(named(a.actor, a.admin_mode === true)));
  return parts;
}

/** "Ana R. and Owen P."; a tag-only (nameless, admin-mode) approver sits at the end. */
function joined(names: readonly NamedActor[]): readonly HeaderPart[] {
  const withName = names.filter((n) => n.name);
  const tagOnly = names.filter((n) => !n.name);
  return [
    ...withName.flatMap((actor, i): HeaderPart[] =>
      i === 0 ? [{ actor }] : [{ text: i === withName.length - 1 ? " and " : ", " }, { actor }],
    ),
    ...tagOnly.map((actor) => ({ actor })),
  ];
}

/**
 * The revision header (U89): "Submitted by Mira K. · approved and applied by Ana R. · 11-17
 * 09:12Z"; "… · approved by Ana R. · applied by Owen P. · …" when they differ; "Submitted and
 * applied by Mira K. · 11-17 09:12Z · no second approval needed" when none was needed. A person
 * with no name drops and the act stays (#308): "Submitted · approved by Ana R. · 11-17 09:12Z".
 */
export function revisionHeader(row: RevisionSummary): readonly HeaderPart[] {
  // A null actor drops its clause, as the table shows a dash.
  if (!row.submitted_by) return appliedLine(row);
  const at = formatShort(new Date(row.applied_at));
  const approval = approvedBy(row);
  const submitter = byClause(named(row.submitted_by));
  if (approval.kind === "not_needed")
    return [
      { text: "Submitted and applied" },
      ...submitter,
      { text: ` · ${at} · no second approval needed` },
    ];
  if (approval.kind === "none") return appliedLine(row);
  const approvals = row.approvals.filter(isApproval);
  const only = approvals.length === 1 ? approvals[0] : undefined;
  const appliedByApprover =
    only !== undefined &&
    only.actor.id !== null &&
    row.applied_by !== null &&
    only.actor.id === row.applied_by.id;
  const names = joined(approval.approvers);
  const named_ = approval.approvers.some((n) => n.name);
  return [
    { text: "Submitted" },
    ...submitter,
    { text: appliedByApprover ? " · approved and applied" : " · approved" },
    ...(named_ ? [{ text: " by " }, ...names] : names),
    ...(appliedByApprover || !row.applied_by
      ? []
      : [{ text: " · applied" }, ...byClause(named(row.applied_by))]),
    { text: ` · ${at}` },
  ];
}
