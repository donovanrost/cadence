import { codeOf, isError, type ApiError } from "@/api";
import { invalidOpDetails } from "./actions.ts";
import { humanize } from "./itemLines.ts";
import type { RefusalOutcome } from "./refusals.ts";

/**
 * #310 (ca-ux 11-20, U79): an apply refusal opens "Not applied:", per code, in the form
 * "Not applied: <why>, so nothing changed. <what to do>." (U20: say nothing changed). Codes other
 * paths word already pass through (null): the checks refusals, the U82 in-use outcome, the
 * server-worded U63/U65 lines, the conversion refusal, and reason_required (the Why field's own
 * message). Errors with no code (dropped, unreadable, a 500) keep failureOutcome's unclear words.
 */
const applyLines = {
  change_set_changed:
    "Not applied: someone changed the staged set while you were looking, so nothing changed. It's been reloaded; check it, then apply again.",
  activation_policy_changed:
    "Not applied: the mission's approval setting changed after this was submitted, so nothing changed. The change set has reopened; check it, then apply or send it for review again.",
  checks_failed:
    "Not applied: a check says NO-GO, so nothing changed. Fix the NO-GO items, then apply again.",
  holds_not_acknowledged:
    "Not applied: some holds aren't acknowledged yet, so nothing changed. Read and acknowledge them, then apply again.",
  holds_blocking:
    "Not applied: a blocking hold stands, so nothing changed. It can't be acknowledged; apply once it clears (the checks show it).",
  catalog_command_in_flight:
    "Not applied: commands started on the affected spacecraft, so nothing changed. Try again when they finish.",
  nothing_staged: "Not applied: nothing is staged, so there's nothing to apply.",
} as const;
type ApplyLineCode = keyof typeof applyLines;
const lineCodes = Object.keys(applyLines).filter((k): k is ApplyLineCode => k in applyLines);

const passThrough = [
  "in_use",
  "conversion_in_progress",
  "telemetry_app_not_installed",
  "telemetry_packet_inputs_required",
  "mission_model_revision_not_approved",
  "mission_model_comparison_failed",
  "reason_required",
  "preview_failed",
  "packet_definition_version_taken",
] as const;

const INVALID = "Not applied: some changes aren't valid, so nothing changed.";
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

/** The apply refusal's words, or null when another path words it (see above). */
export function applyRefusal(error: ApiError): RefusalOutcome | null {
  const serverCode = codeOf(error);
  if (serverCode === null) return null;
  if (passThrough.some((code) => isError(error, code))) return null;
  const code = lineCodes.find((c) => isError(error, c));
  if (code) return { changed: false, sentence: applyLines[code] };
  if (isError(error, "invalid_op") || isError(error, "invalid_params")) {
    const list = invalidList(error);
    return { changed: false, sentence: list ? `${INVALID} ${list}` : INVALID };
  }
  // designers §3: never the server's text as the line; it goes in Technical details.
  return {
    changed: false,
    sentence: "Not applied: Cadence refused this, so nothing changed.",
    technical: `${serverCode}: ${"message" in error ? error.message : ""}`,
  };
}
