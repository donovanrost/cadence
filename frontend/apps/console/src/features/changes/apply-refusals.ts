import { codeOf, isError, type ApiError } from "@/api";
import { invalidOpDetails } from "./actions.ts";
import { humanize } from "./itemLines.ts";
import type { RefusalOutcome } from "./refusals.ts";

/**
 * #310 (ca-ux 11-20, U79): a submit refusal opens by the act its button named, per code: "Not
 * applied: <why>, so nothing changed. <what to do>." or "Not sent for review: …" (#553, #554). U20:
 * say nothing changed. Codes other
 * paths word already pass through (null): the checks refusals, the U82 in-use outcome, the
 * server-worded U63/U65 lines, and reason_required (the Why field's own
 * message). Errors with no code (dropped, unreadable, a 500) keep failureOutcome's unclear words.
 */
/** Per code, by the act the button named (#554): Apply "Not applied:", Request review "Not sent for review:". */
const lines = {
  change_set_changed: {
    apply:
      "Not applied: someone changed the change set while you were looking, so nothing changed. It's been reloaded; check it, then apply again.",
    request_review:
      "Not sent for review: someone changed the change set while you were looking, so nothing changed. It's been reloaded; check it, then send it for review again.",
  },
  activation_policy_changed: {
    apply:
      "Not applied: the mission's approval setting changed while you had this open, so nothing changed. Check whether it now needs review, then apply or send it for review.",
    request_review:
      "Not sent for review: the mission's approval setting changed while you had this open, so nothing changed. Check whether it still needs review, then apply or send it for review.",
  },
  checks_failed: {
    apply:
      "Not applied: a check says NO-GO, so nothing changed. Fix the NO-GO items, then apply again.",
    request_review:
      "Not sent for review: a check says NO-GO, so nothing changed. Fix the NO-GO items, then send it for review again.",
  },
  holds_not_acknowledged: {
    apply:
      "Not applied: some holds aren't acknowledged yet, so nothing changed. Read and acknowledge them, then apply again.",
    request_review:
      "Not sent for review: some holds aren't acknowledged yet, so nothing changed. Read and acknowledge them, then send it for review again.",
  },
  holds_blocking: {
    apply:
      "Not applied: a blocking hold stands, so nothing changed. It can't be acknowledged; apply once it clears (the checks show it).",
    request_review:
      "Not sent for review: a blocking hold stands, so nothing changed. It can't be acknowledged; send it for review once it clears (the checks show it).",
  },
  catalog_command_in_flight: {
    apply:
      "Not applied: commands started on the affected spacecraft, so nothing changed. Try again when they finish.",
    request_review:
      "Not sent for review: commands started on the affected spacecraft, so nothing changed. Try again when they finish.",
  },
  nothing_staged: {
    apply: "Not applied: nothing is staged, so there's nothing to apply.",
    request_review: "Not sent for review: nothing is staged, so there's nothing to review.",
  },
} as const satisfies Record<string, Record<SubmitAct, string>>;
type LineCode = keyof typeof lines;
const lineCodes = Object.keys(lines).filter((k): k is LineCode => k in lines);

/** The submit's act: the button read Apply or Request review. */
export type SubmitAct = "apply" | "request_review";
const OPENER = {
  apply: "Not applied",
  request_review: "Not sent for review",
} as const satisfies Record<SubmitAct, string>;

const passThrough = [
  "in_use",
  "telemetry_app_not_installed",
  "telemetry_packet_inputs_required",
  "mission_model_revision_not_approved",
  "mission_model_comparison_failed",
  "reason_required",
  "preview_failed",
  "packet_definition_version_taken",
] as const;

const SHOWN = 5;

/** "Field: message" by the field's words (no raw paths, #308), up to five, then "and N more". */
function invalidList(error: ApiError): string | null {
  const op = invalidOpDetails(error);
  const errors =
    op?.errors.map((e) => (e.path ? `${humanize(e.path)}: ${e.message}` : e.message)) ??
    paramsList(error);
  if (!errors || errors.length === 0) return null;
  const more = errors.length - SHOWN;
  return `${errors.slice(0, SHOWN).join(" · ")}${more > 0 ? ` · and ${more} more` : ""}`;
}

function paramsList(error: ApiError): readonly string[] | null {
  if (!isError(error, "invalid_params") || !("details" in error)) return null;
  const d = error.details;
  if (d === null || typeof d !== "object" || Array.isArray(d)) return null;
  return Object.entries(d).flatMap(([field, v]) => {
    const messages =
      typeof v === "string"
        ? [v]
        : Array.isArray(v)
          ? v.filter((m): m is string => typeof m === "string")
          : [];
    return messages.map((m) => `${humanize(field)}: ${m}`);
  });
}

/** A submit refusal's words by its act, or null when another path words it (see above). */
export function applyRefusal(error: ApiError, act: SubmitAct = "apply"): RefusalOutcome | null {
  const serverCode = codeOf(error);
  if (serverCode === null) return null;
  if (passThrough.some((code) => isError(error, code))) return null;
  const code = lineCodes.find((c) => isError(error, c));
  if (code) return { changed: false, sentence: lines[code][act] };
  if (isError(error, "invalid_op") || isError(error, "invalid_params")) {
    const list = invalidList(error);
    const invalid = `${OPENER[act]}: some changes aren't valid, so nothing changed.`;
    return { changed: false, sentence: list ? `${invalid} ${list}` : invalid };
  }
  // designers §3: never the server's text as the line; it goes in Technical details.
  return {
    changed: false,
    sentence: `${OPENER[act]}: Cadence refused this, so nothing changed.`,
    technical: `${serverCode}: ${"message" in error ? error.message : ""}`,
  };
}
