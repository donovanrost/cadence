import { codeOf, decoders as d, detailsOf, isError, isKnown, type ApiError } from "@/api/index.ts";
import { formatShort } from "@/ui";
import { REASON_MAX } from "./words.ts";

/** E2 (#546; U109 in #615): withdrawing a catalog revision's approval. */

const when = (iso: string) => formatShort(new Date(iso));
const cap = (s: string) => `${s.charAt(0).toUpperCase()}${s.slice(1)}`;

/** The sheet's consequence lines (U109), read as its description (aria-describedby). */
export const WITHDRAW_LINES = [
  "Spacecraft on it stay on it, but they can't take a new configuration that uses it, and new commands to them meet a hold until they move to an approved version. Nothing that's running stops.",
  // While #600 is open: withdrawn is final (the revision's id comes from its content).
  "This can't be undone for now: the same catalog content can't be approved again until a later Cadence update.",
] as const;

/** After it, a status (B6): "Approval withdrawn. Spacecraft on catalog rev 4 can't take …". */
export const withdrawnLine = (what: string) =>
  `Approval withdrawn. Spacecraft on ${what} can't take a new configuration that uses it.`;

export type WithdrawFailure = Readonly<{
  /** The sheet's line; null when the refusal is the Reason field's own error. */
  text: string | null;
  /** The Reason field's error (422). */
  field?: string;
  /** A code or status the console doesn't word, for Technical details (U20). */
  code?: string;
}>;

const statuses = ["candidate", "approved", "rejected", "retired", "withdrawn"] as const;
const notWithdrawable = d.object({
  status: d.nullable(d.knownText(statuses)),
  decided_by: d.optional(
    d.nullable(d.object({ id: d.nullable(d.string), name: d.nullable(d.string) })),
  ),
  decided_at: d.optional(d.nullable(d.timestamp)),
});

/** U109's refusals; `what` is "catalog rev 4" / "composition 3" / "this catalog revision". */
export function withdrawFailure(
  e: ApiError,
  what: string,
  viewerId: string | null,
): WithdrawFailure {
  if (isError(e, "mission_model_decision_reason_required"))
    return { text: null, field: "Say why." };
  if (isError(e, "mission_model_decision_reason_too_long"))
    return {
      text: null,
      field: `Keep the reason under ${REASON_MAX.toLocaleString("en-US")} characters.`,
    };
  if (isError(e, "mission_model_revision_not_withdrawable"))
    return notWithdrawableLine(e, what, viewerId);
  if (isError(e, "human_mission_model_approver_required"))
    return {
      text: "Not withdrawn: only a person can withdraw an approval, not a service identity. Nothing changed.",
    };
  if (e.kind === "forbidden")
    return { text: "Not withdrawn: only an org admin can withdraw an approval. Nothing changed." };
  const code = codeOf(e);
  const text = "Not withdrawn: Cadence refused this, so nothing changed.";
  return code ? { text, code } : { text };
}

function notWithdrawableLine(e: ApiError, what: string, viewerId: string | null): WithdrawFailure {
  const det = detailsOf(e, notWithdrawable);
  const by = det?.decided_by ?? null;
  const at = det?.decided_at ?? null;
  const known = by !== null && at !== null;
  const name = by?.name ? ` by ${by.name}` : "";
  const status = det?.status ?? null;
  if (status === "candidate")
    return {
      text: `Not withdrawn: ${what} isn't approved, so there's nothing to withdraw. Nothing changed.`,
    };
  if (status === "rejected")
    return {
      text: known
        ? `${cap(what)} was rejected${name} at ${when(at)}, so there's nothing to withdraw. Nothing changed.`
        : `Not withdrawn: ${what} was rejected, so there's nothing to withdraw. Nothing changed.`,
    };
  if (status === "withdrawn") {
    // compared-as-text: actor ids are opaque tokens; equal means the viewer withdrew it
    if (known && viewerId !== null && by.id === viewerId)
      return { text: `You already withdrew its approval at ${when(at)}. Reload to see it.` };
    return {
      text: known
        ? `${cap(what)}'s approval was already withdrawn${name} at ${when(at)}, so nothing changed. Reload to see it.`
        : "Not withdrawn: its approval was already withdrawn, so nothing changed. Reload to see it.",
    };
  }
  if (status === "retired")
    return {
      text: `Not withdrawn: ${what} is retired, so there's nothing to withdraw. Nothing changed.`,
    };
  // "approved" (a race) or a status the console doesn't know: U109's catch-all, its status in
  // Technical details.
  const raw = status === null ? null : isKnown(status) ? status : status.unrecognized;
  return {
    text: `Not withdrawn: ${what} can't be withdrawn as it stands, so nothing changed. Reload to see it.`,
    code: raw ?? codeOf(e) ?? "mission_model_revision_not_withdrawable",
  };
}
