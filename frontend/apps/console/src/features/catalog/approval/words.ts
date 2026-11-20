import {
  codeOf,
  decoders as d,
  detailsOf,
  isError,
  isKnown,
  vocabularyText,
  type ApiError,
  type Unrecognized,
} from "@/api/index.ts";
import { formatCount, formatShort } from "@/ui";
import type { Comparison, DeclarationKind, ModelRevision } from "./api.ts";
import {
  actorInSentence,
  compositionInSentence,
  isComposed,
  madeOfParts,
  type Composition,
} from "../composition.ts";

/** ux U65 words. Visible text says "catalog rev 4"; the model revision id is Technical details. */

const KIND_WORDS: Readonly<Record<DeclarationKind, string>> = {
  command: "Commands",
  command_argument: "Command arguments",
  command_argument_type: "Argument types",
  command_encoding: "Command encodings",
  command_constraint: "Command constraints",
  command_verifier: "Command verifiers",
  parameter: "Telemetry points",
  parameter_type: "Point types",
  container: "Containers",
  calibrator: "Calibrators",
  algorithm: "Algorithms",
  monitoring_policy: "Monitoring policies",
  stream: "Streams",
  service: "Services",
  extension: "Extensions",
  unit: "Units",
  space_system: "Space systems",
};

/** "Commands"; an unknown kind reads its key with spaces. */
export function kindWord(kind: DeclarationKind | Unrecognized): string {
  if (isKnown(kind)) return KIND_WORDS[kind];
  const w = kind.unrecognized.replaceAll("_", " ");
  return w.charAt(0).toUpperCase() + w.slice(1);
}

type Section = Comparison["sections"][number];
/** "Commands: 3 added · 1 changed" (zeros dropped); null when nothing changed in it. */
export function sectionLine(s: Section): string | null {
  const parts = [
    s.added ? `${s.added} added` : null,
    s.removed ? `${s.removed} removed` : null,
    s.changed ? `${s.changed} changed` : null,
  ].filter((p): p is string => p !== null);
  return parts.length ? `${kindWord(s.kind)}: ${parts.join(" · ")}` : null;
}

/** RISK LOW / RISK MEDIUM neutral; RISK HIGH caution (with ▲ from the tag). */
export function riskTag(c: Comparison): { label: string; state: "neutral" | "caution" } {
  const word = isKnown(c.risk) ? c.risk : c.risk.unrecognized;
  return { label: `RISK ${word.toUpperCase()}`, state: c.risk === "high" ? "caution" : "neutral" };
}

const against = (c: Comparison) =>
  c.against ? ` against rev ${c.against.catalog_revision_number}` : "";
/**
 * "Comparison passed against rev 3" / "Comparison didn't pass against rev 3". U90: with nothing
 * earlier (against null) it was never compared, whatever `passed` says.
 */
export const verdictLine = (c: Comparison) =>
  c.against === null
    ? "Not compared: there's no earlier configuration"
    : `Comparison ${c.passed ? "passed" : "didn't pass"}${against(c)}`;
/** The verdict's mark: U90's not-compared is caution, never the pass glyph. */
export const verdictState = (c: Comparison): "nominal" | "crit" | "caution" =>
  c.against === null ? "caution" : c.passed ? "nominal" : "crit";

/** U90's callout (never folded away): nothing earlier, so every declaration is new and unchecked. */
export function noEarlierLine(c: Comparison): string | null {
  if (c.against !== null) return null;
  const n = c.sections.reduce((sum, s) => sum + s.added, 0);
  const all = n > 1 ? `All ${formatCount(n)} declarations are new` : "Every declaration is new";
  return `There's no earlier configuration for this mission, so there was nothing to compare it with. ${all}, and none has been checked against an earlier version.`;
}
/** U90: above Approve when nothing was compared. */
export const NO_EARLIER_APPROVE = "Approving it accepts every declaration as new.";

/** The director's condition: never folded away, never shown as passed. */
export const REPLAY_NOT_RUN =
  "Replay: not run. There's no qualification corpus, so this revision hasn't been replayed against recorded telemetry.";

/** Replay lines other than not_run (that one is the callout). */
export function replayLine(c: Comparison): string | null {
  const r = c.replay;
  if (r.status === "not_run") return null;
  if (r.status === "not_required") return "Replay: not needed for a low-risk change.";
  if (r.status === "passed")
    return `Replay: passed (${r.cases} recorded ${r.cases === 1 ? "case" : "cases"}).`;
  if (r.status === "failed") return `Replay: ${r.failed_cases.length} of ${r.cases} cases failed.`;
  return `Replay: ${r.status.unrecognized.replaceAll("_", " ")}.`;
}

const when = (iso: string) => formatShort(new Date(iso));

/**
 * U109, a composed base: "Imported by Mira K. (Bus catalog rev 4) and Ana R. (Payload catalog
 * rev 2)". People, not events, so no time; a catalog with no named importer drops; none named:
 * null (no line).
 */
export function composedImportersLine(r: ModelRevision): string | null {
  const c = r.composition;
  if (!isComposed(c)) return null;
  const parts = madeOfParts(c);
  const named = c.imported_layers.flatMap((l, i) => {
    const people = (r.importers ?? [])
      .find((x) => x.layer_id === l.layer_id)
      ?.importers.map(actorInSentence)
      .filter((n): n is string => n !== null);
    return people && people.length > 0 ? [`${joinAnd(people)} (${parts[i] ?? ""})`] : [];
  });
  return named.length > 0 ? `Imported by ${joinAnd(named)}.` : null;
}

/** "Composed by Owen P. at 11-20 09:12Z." (U29; U103's forms); null for the migration's (no creator). */
export function composedByLine(c: Composition): string | null {
  const who = actorInSentence(c.created_by);
  if (c.created_by === null) return null;
  return who
    ? `Composed by ${who} at ${when(c.created_at)}.`
    : `Composed at ${when(c.created_at)}.`;
}

const joinAnd = (xs: readonly string[]) =>
  xs.length <= 1 ? (xs[0] ?? "") : `${xs.slice(0, -1).join(", ")} and ${xs.at(-1)}`;

/** "Imported by Mira K. at 11-14 22:10Z."; null when the importer isn't recorded (its own line). */
export function importerLine(r: ModelRevision): string | null {
  if (!r.imported_by) return null;
  const by = r.imported_by.name ? ` by ${r.imported_by.name}` : "";
  return `Imported${by}${r.imported_at ? ` at ${when(r.imported_at)}` : ""}.`;
}

/** "Approved by Ana R. at 11-15 09:12Z." / "Rejected by …: “Wrong FSW build.”" */
export function decidedLine(r: ModelRevision): string | null {
  const dcs = r.decision;
  if (!dcs) return null;
  const what = vocabularyText(dcs.kind, {
    approved: "Approved",
    rejected: "Rejected",
    withdrawn: "Withdrawn",
  });
  // U109 (#615): a withdrawal says why, as a rejection does.
  const why =
    (dcs.kind === "rejected" || dcs.kind === "withdrawn") && dcs.reason
      ? `: “${dcs.reason.trim()}”`
      : "";
  const by = dcs.by?.name ? ` by ${dcs.by.name}` : "";
  return `${what}${by} at ${when(dcs.at)}${why}.`;
}

/** U65 row tag: NEEDS APPROVAL (caution) / APPROVED / REJECTED / WITHDRAWN (off; E2); none otherwise. */
export function approvalTag(
  status: "candidate" | "approved" | "rejected" | "retired" | "withdrawn" | Unrecognized,
): { label: string; state: "caution" | "neutral" | "off" } | null {
  if (status === "candidate") return { label: "NEEDS APPROVAL", state: "caution" };
  if (status === "approved") return { label: "APPROVED", state: "neutral" };
  if (status === "rejected") return { label: "REJECTED", state: "neutral" };
  if (status === "withdrawn") return { label: "WITHDRAWN", state: "off" };
  return null;
}

/**
 * U109: what a decision names. A composed base is "composition 3" ("this composition" with no
 * number); one catalog stays "rev 4" ("this revision" with none), word for word as before D4.
 */
export function revisionWord(r: ModelRevision): string {
  if (isComposed(r.composition)) return compositionInSentence(r.composition);
  return r.catalog_revision ? `rev ${r.catalog_revision.number}` : "this revision";
}

/** U109's up-front lines for a composed base ("You …, so another org admin approves composition 3."). */
function composedCannotDecide(r: ModelRevision, c: Composition): string | null {
  const why = r.cannot_decide_because;
  const name = compositionInSentence(c);
  const service = r.cannot_decide_details?.via_service ?? null;
  // U100: "Nightly planner, a service identity you're accountable for, …"; nameless, no commas
  // (mms-ux and ca-ux on #609): "A service identity you're accountable for …".
  const svc = service
    ? service.name
      ? `${service.name}, a service identity you're accountable for,`
      : "A service identity you're accountable for"
    : null;
  if (why === "self_approval")
    return svc
      ? `${svc} imported one of its catalogs, so another org admin approves ${name}.`
      : `You imported one of its catalogs, so another org admin approves ${name}.`;
  if (why === "composer")
    return svc
      ? `${svc} chose this combination of catalogs, so another org admin approves ${name}.`
      : `You chose this combination of catalogs, so another org admin approves ${name}.`;
  return null;
}

/** Why the viewer has no decision buttons (null: they can decide, or it's already decided). */
export function cannotDecideLine(r: ModelRevision): string | null {
  const why = r.cannot_decide_because;
  if (why === null || why === "not_approvable") return null;
  if (isComposed(r.composition)) {
    const composed = composedCannotDecide(r, r.composition);
    if (composed) return composed;
  }
  if (why === "self_approval")
    return "You imported this revision, so another org admin has to approve it.";
  if (why === "plans_not_ready")
    return "Cadence is still preparing this revision. Try again in a moment.";
  if (why === "not_admin") return "Org admins approve catalog revisions.";
  // #308 (d): a reason the console doesn't word reads plainly; its code goes in Technical details.
  return "You can't approve or reject this revision.";
}

/** ux U88: why Approve is off while Reject stays (null: Approve isn't blocked). */
export function cannotApproveLine(r: ModelRevision): string | null {
  const why = r.cannot_approve_because;
  if (why === null || why === undefined) return null;
  if (why === "not_in_catalog")
    return "The catalog doesn't list this revision, so it can't be approved. To approve it, import its file as a new catalog revision. Reject it to clear it from the queue.";
  return "This revision can't be approved. Reject it to clear it from the queue.";
}

/** #308 (d): the code behind a blocked decision the console doesn't word, for Technical details. */
export function unwordedBlockCode(r: ModelRevision): string | null {
  const decide = r.cannot_decide_because;
  if (decide !== null && !isKnown(decide)) return decide.unrecognized;
  const approve = r.cannot_approve_because;
  if (approve !== null && approve !== undefined && !isKnown(approve)) return approve.unrecognized;
  return null;
}

/** api: a reject reason is at most 2,000 characters (the sheet's limit too). */
export const REASON_MAX = 2000;

/** The decision whose refusal is being worded (designers §3: a refusal opens with its act). */
export type DecisionAct = "approve" | "reject";

export type DecisionFailure = Readonly<{
  text: string;
  /** Offer Run comparison (approve only). */
  runAgain: boolean;
  /** U88: the refusal's way on is the catalog. */
  openCatalog?: true;
  /** A code the console doesn't word, for Technical details (C1). */
  code?: string;
}>;

/**
 * U65 approve and reject refusals (#312; audit C1, C2). Each opens with its act: "Not approved:"
 * or "Not rejected:"; reject has its own lines, never approve's. A code the console doesn't word
 * reads the act's fallback, with the code in Technical details, never the server's message.
 */
export function decisionFailure(
  e: ApiError,
  rev: number | null,
  act: DecisionAct = "approve",
  viewerId: string | null = null,
  composedName: string | null = null,
): DecisionFailure {
  const base = (text: string, runAgain = false) => ({ text, runAgain });
  if (isError(e, "mission_model_decision_reason_required")) return base("Give a reason first.");
  if (isError(e, "mission_model_decision_reason_too_long"))
    return base(`Keep the reason under ${REASON_MAX.toLocaleString("en-US")} characters.`);
  return act === "approve" ? approveFailure(e, rev, viewerId, composedName) : rejectFailure(e);
}

const notApprovableDetails = d.object({
  status: d.nullable(
    d.knownText(["candidate", "approved", "rejected", "retired", "withdrawn"] as const),
  ),
});

const alreadyApprovedDetails = d.object({
  decided_by: d.nullable(d.object({ id: d.nullable(d.string), name: d.nullable(d.string) })),
  decided_at: d.nullable(d.timestamp),
});

/**
 * #260 (#613; mms-ux): approving a revision someone already approved. The viewer: "You already
 * approved catalog rev 4 at 11-20 06:52Z. Reload to see it." Someone else: "Catalog rev 4 was
 * already approved by Ana R. at …, so your approval wasn't recorded. Reload to see it." Neither
 * known: "Not approved: catalog rev 4 was already approved, so …". A nameless approver drops "by".
 */
function alreadyApproved(
  e: ApiError,
  rev: number | null,
  viewerId: string | null,
  composedName: string | null,
): string {
  // U109: a composed base is "composition 3" ("this composition"); one catalog as mms-ux's lines.
  const what = composedName ?? (rev === null ? "this catalog revision" : `catalog rev ${rev}`);
  const What = `${what.charAt(0).toUpperCase()}${what.slice(1)}`;
  const det = detailsOf(e, alreadyApprovedDetails);
  const by = det?.decided_by ?? null;
  const at = det?.decided_at ?? null;
  if (by === null || at === null)
    return `Not approved: ${what} was already approved, so your approval wasn't recorded. Reload to see it.`;
  if (viewerId !== null && by.id === viewerId)
    return `You already approved ${what} at ${when(at)}. Reload to see it.`;
  const name = by.name ? ` by ${by.name}` : "";
  return `${What} was already approved${name} at ${when(at)}, so your approval wasn't recorded. Reload to see it.`;
}

function approveFailure(
  e: ApiError,
  rev: number | null,
  viewerId: string | null,
  composedName: string | null,
): DecisionFailure {
  const base = (text: string, runAgain = false) => ({ text, runAgain });
  if (isError(e, "mission_model_revision_already_approved"))
    return base(alreadyApproved(e, rev, viewerId, composedName));
  if (isError(e, "mission_model_revision_not_in_catalog"))
    return {
      ...base(
        "Not approved: the catalog doesn't list this revision. Your approval wasn't recorded. To approve it, import its file as a new catalog revision.",
      ),
      openCatalog: true,
    };
  if (isError(e, "mission_model_self_approval_forbidden"))
    return base(
      "Not approved: you imported this revision, so another org admin has to approve it. Your approval wasn't recorded.",
    );
  if (isError(e, "mission_model_comparison_not_passed"))
    return base(
      `Not approved: the comparison${rev === null ? "" : ` with rev ${rev}`} didn't pass. Your approval wasn't recorded.`,
    );
  if (isError(e, "mission_model_comparison_mismatch"))
    return base(
      "Not approved: the comparison is out of date. Your approval wasn't recorded. Run it again.",
      true,
    );
  if (isError(e, "mission_model_runtime_plans_not_ready"))
    return base(
      "Not approved: Cadence is still preparing this revision. Your approval wasn't recorded. Try again in a moment.",
    );
  if (isError(e, "mission_model_revision_not_approvable")) {
    // E2 (#546; mms-ux): a withdrawn revision says so; the page normally shows no Approve then.
    if (detailsOf(e, notApprovableDetails)?.status === "withdrawn") {
      const what = composedName ?? (rev === null ? "this catalog revision" : `catalog rev ${rev}`);
      return base(
        `Not approved: ${what}'s approval was withdrawn, and it can't be approved again for now. Your approval wasn't recorded.`,
      );
    }
    return base(
      "Not approved: this revision was already approved, rejected or replaced, so your approval wasn't recorded.",
    );
  }
  if (isError(e, "human_mission_model_approver_required"))
    return base(
      "Not approved: only a person can approve a catalog revision, not a service identity. Your approval wasn't recorded.",
    );
  if (e.kind === "forbidden")
    return base("Not approved: only an org admin can approve this. Your approval wasn't recorded.");
  return withCode(
    base("Not approved: Cadence refused this approval. Your approval wasn't recorded."),
    e,
  );
}

function rejectFailure(e: ApiError): DecisionFailure {
  const base = (text: string) => ({ text, runAgain: false });
  if (isError(e, "mission_model_revision_not_approvable"))
    return base(
      "Not rejected: this revision was already approved, rejected or replaced, so nothing changed.",
    );
  if (isError(e, "human_mission_model_approver_required"))
    return base(
      "Not rejected: only a person can reject a catalog revision, not a service identity. Nothing changed.",
    );
  if (e.kind === "forbidden")
    return base("Not rejected: only an org admin can reject this. Nothing changed.");
  return withCode(base("Not rejected: Cadence refused this rejection, so nothing changed."), e);
}

const withCode = (f: DecisionFailure, e: ApiError): DecisionFailure => {
  const code = codeOf(e);
  return code ? { ...f, code } : f;
};
