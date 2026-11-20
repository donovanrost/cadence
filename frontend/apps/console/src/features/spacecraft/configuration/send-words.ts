import { codeOf, detailsOf, decoders as d, isError, isKnown, type ApiError } from "@/api/index.ts";
import type { ConfigurationSnapshot, SubmitResult } from "./api.ts";
import { catalogWord, draftDiffers, setupSteps } from "./words.ts";

/** #595c (U94): sending a spacecraft's saved configuration draft for activation. */

const vWord = (s: ConfigurationSnapshot) =>
  s.saved_version === null ? "the draft" : `v${s.saved_version}`;

/** U94: `Activate v4` without approval, `Request approval for v4` with it. */
export const needsApproval = (s: ConfigurationSnapshot) =>
  !(isKnown(s.approval.requirement) && s.approval.requirement === "direct");
export const sendLabel = (s: ConfigurationSnapshot) => {
  const v = s.saved_version === null ? "" : ` v${s.saved_version}`;
  return needsApproval(s) ? `Request approval for${v || " it"}` : `Activate${v}`;
};

/** U94: where the approval setting comes from ("Mission setting" / …), beside Approval settings. */
export function sourceLine(s: ConfigurationSnapshot): string {
  const src = s.approval.source;
  if (!isKnown(src)) return "Approval setting";
  return {
    overridden: "Mission setting",
    organization: "Organization default",
    inherited: "Organization default",
    enforced: "Set by the organization",
  }[src];
}

/**
 * U94's disabled reasons (A6), first that applies: unsaved, someone else saved, steps left,
 * nothing changed, already waiting, no right to request.
 */
export function sendBlocked(
  s: ConfigurationSnapshot,
  state: Readonly<{ dirty: boolean; conflict: boolean; sending: boolean }>,
): string | null {
  if (state.sending) return "Sending…";
  if (state.dirty) return "Save the draft first.";
  if (state.conflict || s.external_changes) return "Choose which version to keep first.";
  if (setupSteps(s.document, s.name, s.switches.telemetry_enabled.value).length > 0)
    return "Finish the steps above first.";
  if (s.saved_version === null || (s.active !== null && !draftDiffers(s)))
    return "The draft matches the active configuration.";
  if (s.review && isKnown(s.review.state) && s.review.state === "approval_pending")
    return `${s.review.version === null ? "The draft" : `v${s.review.version}`} is waiting for approval.`;
  if (!s.approval.can_request) return "You can't activate configurations on this mission.";
  return null;
}

export type SendOutcome = Readonly<{
  tone: "info" | "nominal" | "caution";
  text: string;
  /** L10's page for `Open request`. */
  requestId: string | null;
}>;

/** U94's results, by submit's `state`. */
export function sendOutcome(r: SubmitResult, s: ConfigurationSnapshot): SendOutcome {
  const v = vWord(s);
  if (r.state === "approval_pending")
    return {
      tone: "info",
      text: `Sent for approval. Another person approves ${v} in Setup › Changes.`,
      requestId: r.request_id,
    };
  if (r.state === "active")
    return { tone: "nominal", text: `${v} is active on ${s.name}.`, requestId: null };
  return {
    tone: "caution",
    text: `${v} is approved, but Cadence couldn't confirm it was applied yet.`,
    requestId: s.review?.id ?? null,
  };
}

/** U94: the request's state in the workspace, with `Open request` (U29); null when none. */
export function reviewLine(s: ConfigurationSnapshot): string | null {
  const r = s.review;
  if (!r || !isKnown(r.state)) return null;
  const v = r.version === null ? "the draft" : `v${r.version}`;
  const V = r.version === null ? "The draft" : `v${r.version}`;
  switch (r.state) {
    case "approval_pending":
      return `${V} is waiting for approval.`;
    case "rejected":
      return `${V} was rejected. Change the draft and send it again.`;
    case "withdrawn":
      return `The request for ${v} was withdrawn.`;
    case "superseded":
      return "Replaced by a newer request.";
    case "stale":
      return `${s.name}'s configuration changed after ${v} was sent, so it can't be approved. Send it again.`;
    case "approved":
    case "active":
      return null;
  }
}

const notApproved = d.object({
  mission_model_revision_ids: d.array(d.token, 100),
  catalog_revision_numbers: d.array(d.nullable(d.integer), 100),
});

export type SendRefusal = Readonly<{
  text: string;
  code?: string;
  /** U65: `Open rev 14` for one unapproved catalog revision (its model revision's page). */
  openRevision?: Readonly<{ number: number; revisionId: string }>;
  openProfile?: true;
}>;

/** "catalog revs 4 and 5" / "catalog rev 14" / "a catalog revision". */
function revsWord(ns: readonly (number | null)[]): string {
  const known = ns.filter((n): n is number => n !== null);
  if (known.length === 0) return ns.length > 1 ? "these catalog revisions" : "a catalog revision";
  if (known.length === 1 && ns.length === 1) return `catalog rev ${known[0] ?? ""}`;
  const list =
    known.length === 1
      ? `${known[0] ?? ""}`
      : `${known.slice(0, -1).join(", ")} and ${known.at(-1) ?? ""}`;
  return `catalog revs ${list}`;
}

/** U94's submit refusals, "Not sent: …". */
export function sendRefusal(e: ApiError, s: ConfigurationSnapshot): SendRefusal {
  const craft = s.name;
  if (isError(e, "spacecraft_configuration_review_stale"))
    return {
      text: `Not sent: ${craft}'s active configuration changed since you loaded this. Check the comparison and send it again.`,
    };
  if (isError(e, "activation_policy_changed"))
    return {
      text: "Not sent: the mission's approval setting changed. Check it and send it again.",
    };
  if (isError(e, "spacecraft_configuration_review_unavailable"))
    return { text: "Not sent: save the draft and choose which version to keep first." };
  if (isError(e, "spacecraft_catalog_required"))
    return { text: "Not sent: choose a catalog revision first." };
  if (isError(e, "spacecraft_packet_inputs_required"))
    return {
      text: `Not sent: telemetry is on for ${craft}, so choose a packet source and the APIDs to decode first.`,
    };
  // The server's own line (spacecraft_workspace_words.ex; mms-ux: one wording).
  if (isError(e, "spacecraft_switch_set_by_change_set"))
    return {
      text: `Not sent: a change set turned Telemetry or Commanding on or off for ${craft} after this draft was saved. Save the draft again, then send it.`,
    };
  // #534's race (#549, mms-ux's words, as the server sends them); the draft is untouched.
  if (isError(e, "packet_definition_version_taken"))
    return {
      text: "Not sent: another change saved a packet definition at the same moment. Send it again.",
    };
  if (isError(e, "mission_model_revision_not_approved")) {
    const det = detailsOf(e, notApproved);
    const ns = det?.catalog_revision_numbers ?? [];
    const n = ns.length === 1 ? (ns[0] ?? null) : null;
    const id = det?.mission_model_revision_ids[0] ?? null;
    const text =
      ns.length > 1
        ? `Not sent: ${revsWord(ns)} aren't approved yet. An org admin approves them in Setup › Catalog first.`
        : `Not sent: ${revsWord(ns)} isn't approved yet. An org admin approves it in Setup › Catalog first.`;
    return n !== null && id !== null
      ? { text, openRevision: { number: n, revisionId: id } }
      : { text };
  }
  if (isError(e, "spacecraft_catalog_set_by_profile"))
    return {
      text: `Not sent: ${craft}'s profile sets its catalog revision. Change it on the profile, through Setup › Changes.`,
      openProfile: true,
    };
  if (isError(e, "spacecraft_catalog_unavailable"))
    return {
      text: `Not sent: ${catalogWord(s, s.document.catalog_revision_id)} isn't one of this mission's catalog revisions. Choose another.`,
    };
  if (isError(e, "spacecraft_source_limit_exceeded"))
    return {
      text: `${craft} has more packet sources than one configuration can carry, so it can't be shown or sent. Remove some in Setup › Comms.`,
    };
  if (isError(e, "spacecraft_not_found")) return { text: "This spacecraft isn't on this mission." };
  if (e.kind === "forbidden") return { text: `You can't change ${craft}'s configuration.` };
  const code = codeOf(e);
  return code ? { text: "Not sent.", code } : { text: "Not sent." };
}
