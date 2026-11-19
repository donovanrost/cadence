import { decoders, detailsOf, isError, type ApiError } from "@/api";
import type { FailureOutcome } from "./actions.ts";

/**
 * TEMPORARY, deleted with 9ac6dc8ee (ux U79; api 409 conversion_in_progress): while a route
 * conversion batch is staged, no other change can be staged in the mission. Shown wherever the stage
 * was tried; the draft stays in its form.
 */
const details = decoders.object({
  change_set_id: decoders.token,
  batch: decoders.optional(decoders.nullable(decoders.integer)),
});

export function conversionInProgress(error: ApiError): FailureOutcome | null {
  if (!isError(error, "conversion_in_progress")) return null;
  const batch = detailsOf(error, details)?.batch;
  const what =
    batch == null
      ? "The route conversion is staged"
      : `Batch ${batch} of the route conversion is staged`;
  return {
    changed: false,
    sentence: `${what}, so other changes can't be staged in this mission until it's applied or discarded.`,
    link: { label: "Open change set", to: { name: "setup.changes" } },
  };
}
