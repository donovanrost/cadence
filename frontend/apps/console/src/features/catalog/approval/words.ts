import { isError, isKnown, vocabularyText, type ApiError, type Unrecognized } from "@/api/index.ts";
import { formatCount, formatShort } from "@/ui";
import type { Comparison, DeclarationKind, ModelRevision } from "./api.ts";

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

/** "Imported by Mira K. at 11-14 22:10Z."; null when the importer isn't recorded (its own line). */
export function importerLine(r: ModelRevision): string | null {
  if (!r.imported_by) return null;
  return `Imported by ${r.imported_by.name}${r.imported_at ? ` at ${when(r.imported_at)}` : ""}.`;
}

/** "Approved by Ana R. at 11-15 09:12Z." / "Rejected by …: “Wrong FSW build.”" */
export function decidedLine(r: ModelRevision): string | null {
  const dcs = r.decision;
  if (!dcs) return null;
  const what = vocabularyText(dcs.kind, { approved: "Approved", rejected: "Rejected" });
  const why = dcs.kind === "rejected" && dcs.reason ? `: “${dcs.reason.trim()}”` : "";
  return `${what} by ${dcs.by.name} at ${when(dcs.at)}${why}.`;
}

/** U65 row tag: NEEDS APPROVAL (caution) / APPROVED / REJECTED; none otherwise. */
export function approvalTag(
  status: "candidate" | "approved" | "rejected" | "retired" | Unrecognized,
): { label: string; state: "caution" | "neutral" } | null {
  if (status === "candidate") return { label: "NEEDS APPROVAL", state: "caution" };
  if (status === "approved") return { label: "APPROVED", state: "neutral" };
  if (status === "rejected") return { label: "REJECTED", state: "neutral" };
  return null;
}

/** Why the viewer has no decision buttons (null: they can decide, or it's already decided). */
export function cannotDecideLine(r: ModelRevision): string | null {
  const why = r.cannot_decide_because;
  if (why === null || why === "not_approvable") return null;
  if (why === "self_approval")
    return "You imported this revision, so another org admin has to approve it.";
  if (why === "plans_not_ready")
    return "Cadence is still preparing this revision. Try again in a moment.";
  if (why === "not_admin") return "Org admins approve catalog revisions.";
  return why.unrecognized.replaceAll("_", " ");
}

/** ux U88: why Approve is off while Reject stays (null: Approve isn't blocked). */
export function cannotApproveLine(r: ModelRevision): string | null {
  const why = r.cannot_approve_because;
  if (why === null || why === undefined) return null;
  if (why === "not_in_catalog")
    return "The catalog doesn't list this revision, so it can't be approved. To approve it, import its file as a new catalog revision. Reject it to clear it from the queue.";
  return why.unrecognized.replaceAll("_", " ");
}

/** api: a reject reason is at most 2,000 characters (the sheet's limit too). */
export const REASON_MAX = 2000;

/** U65 approve/reject refusals; `runAgain` offers Run comparison. */
export function decisionFailure(
  e: ApiError,
  rev: number | null,
): Readonly<{ text: string; runAgain: boolean; openCatalog?: true }> {
  const base = (text: string, runAgain = false) => ({ text, runAgain });
  if (isError(e, "mission_model_revision_not_in_catalog"))
    return {
      ...base(
        "Not approved: the catalog doesn't list this revision. To approve it, import its file as a new catalog revision.",
      ),
      openCatalog: true,
    };
  if (isError(e, "mission_model_self_approval_forbidden"))
    return base(
      "Not approved: you imported this revision, so another org admin has to approve it.",
    );
  if (isError(e, "mission_model_comparison_not_passed"))
    return base(
      `Not approved: the comparison${rev === null ? "" : ` with rev ${rev}`} didn't pass.`,
    );
  if (isError(e, "mission_model_comparison_mismatch"))
    return base("Not approved: the comparison is out of date. Run it again.", true);
  if (isError(e, "mission_model_runtime_plans_not_ready"))
    return base("Not approved: Cadence is still preparing this revision. Try again in a moment.");
  if (isError(e, "mission_model_revision_not_approvable"))
    return base("Not approved: this revision was already approved, rejected or replaced.");
  if (isError(e, "human_mission_model_approver_required"))
    return base("Not approved: a person has to approve this, not a service identity.");
  if (isError(e, "mission_model_decision_reason_required")) return base("Give a reason first.");
  if (isError(e, "mission_model_decision_reason_too_long"))
    return base(`Keep the reason under ${REASON_MAX.toLocaleString("en-US")} characters.`);
  if (e.kind === "forbidden") return base("Nothing changed: only an org admin can decide this.");
  return base(
    `Nothing changed: ${"message" in e ? e.message.replace(/[.!?]+$/, "") : "the server didn't say why"}.`,
  );
}
