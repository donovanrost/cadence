import { decoders as d } from "@/api/index.ts";

/**
 * U91 (api's admission-alert shape, final 11-17): mission_runtime's extra fields, spread into the
 * attention reader. Both optional (readers first: api ships them after this lands).
 */
export const runtimeFields = {
  /**
   * contact_start no_runtime_spec: no_configuration | configuration_unverifiable (api U91).
   * mission_runtime spec_mismatch: the field that failed to verify, opaque, so it reads as
   * unrecognized with its raw text kept (Technical details only, never branched on).
   */
  reason_detail: d.optional(
    d.nullable(d.knownText(["no_configuration", "configuration_unverifiable"] as const)),
  ),
  /** The mission's pass in progress (window open now), else the next one within 2 h, else null. */
  next_pass: d.optional(
    d.nullable(
      d.object({
        contact_id: d.token,
        spacecraft_id: d.nullable(d.token),
        // free-text: the spacecraft's display name
        spacecraft_name: d.nullable(d.string),
        /** The event log's contact station (Reads.EventContacts). */
        station: d.nullable(
          d.object({
            // free-text: the station's display name
            name: d.string,
            // free-text: a station's code (SVA), an open set shown as is
            code: d.nullable(d.token),
          }),
        ),
        /** The AOS. */
        starts_at: d.timestamp,
        ends_at: d.nullable(d.timestamp),
        /** Inside its window now. */
        in_progress: d.boolean,
        /** Its contact actually started (false before AOS, or when it couldn't start). */
        started: d.optional(d.boolean),
      }),
    ),
  ),
};
