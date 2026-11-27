import { isKnown, type Unrecognized } from "@/api/index.ts";

/**
 * Why a provider can't use a spacecraft's orbit (#972; setup.md "provider ephemeris spacecraft",
 * ops.md `provider_ephemeris`): the cause, and for failed and not_ready a closed reason code. A
 * provider's own text is never stored or shown.
 */
export const ephemerisCauses = ["norad_id_missing", "failed", "not_ready"] as const;
export type EphemerisCause = (typeof ephemerisCauses)[number];

/** failed: one per provider error category, plus two of Cadence's own. */
export const failedReasons = [
  "provider_invalid_request",
  "provider_authentication_failed",
  "provider_authorization_failed",
  "provider_unsupported_capability",
  "provider_not_found",
  "provider_conflict",
  "provider_no_capacity",
  "provider_not_ready",
  "provider_rate_limited",
  "provider_unavailable",
  "provider_timeout",
  "provider_ambiguous_outcome",
  "provider_malformed_response",
  "provider_error",
  "provider_version_not_found",
  "other",
] as const;
type FailedReason = (typeof failedReasons)[number];

/** not_ready: the scheduling refusals on a routing rule that binds the spacecraft here. */
export const notReadyReasons = [
  "mission_provider_not_validated",
  "mission_provider_not_active",
  "mission_provider_not_found",
  // ground #986.
  "mission_provider_archived",
  "mission_provider_profiles_not_synced",
  "provider_service_profile_not_active",
  "provider_delivery_profile_not_ready",
  "provider_profile_version_not_available",
  "provider_profile_direction_not_supported",
  "provider_profiles_not_compatible",
  "provider_route_not_ready",
  "invalid_provider_profile_reference",
  "transport_not_found",
  "transport_not_active",
  "transport_provider_snapshot_mismatch",
  "transport_runtime_profile_mismatch",
  "transport_runtime_profile_not_materialized",
  "direct_transport_not_provider_schedulable",
  "contact_link_assignment_not_found",
  "contact_path_template_not_found",
  "source_endpoint_not_found",
  "missing_provider_spacecraft_reference",
  // #983 at 32515114a.
  "missing_downlink_path",
  "spacecraft_not_found",
  "no_ready_route",
] as const;
type NotReadyReason = (typeof notReadyReasons)[number];

const failedWords: Readonly<Record<FailedReason, string>> = {
  provider_invalid_request: "The provider refused the orbit as invalid.",
  provider_authentication_failed: "The provider didn't accept Cadence's credentials.",
  provider_authorization_failed: "The provider doesn't allow this account to upload orbits.",
  provider_unsupported_capability: "The provider doesn't support orbit uploads.",
  provider_not_found: "The provider doesn't know these spacecraft.",
  provider_conflict: "The provider refused the orbit because of a conflict.",
  provider_no_capacity: "The provider has no capacity to take orbits right now.",
  provider_not_ready: "The provider isn't ready to take orbits yet.",
  provider_rate_limited: "The provider is limiting requests.",
  provider_unavailable: "The provider couldn't be reached.",
  provider_timeout: "The provider didn't answer in time.",
  provider_ambiguous_outcome: "The provider's answer didn't say whether it took the orbit.",
  provider_malformed_response: "The provider's answer couldn't be read.",
  provider_error: "The provider returned an error.",
  provider_version_not_found: "The provider version these routes use is gone.",
  other: "The upload failed.",
};

const notReadyWords: Readonly<Record<NotReadyReason, string>> = {
  mission_provider_not_validated: "The provider version hasn't validated.",
  mission_provider_not_active: "The provider version isn't active.",
  mission_provider_not_found: "The provider version these routes pin is gone.",
  mission_provider_archived: "The provider is archived.",
  mission_provider_profiles_not_synced: "The provider's profiles haven't synced.",
  provider_service_profile_not_active: "The route's service profile isn't active.",
  provider_delivery_profile_not_ready: "The route's delivery profile isn't ready.",
  provider_profile_version_not_available: "The route's profile version isn't available.",
  provider_profile_direction_not_supported: "The route's profiles don't support downlink.",
  provider_profiles_not_compatible: "The route's service and delivery profiles don't match.",
  provider_route_not_ready: "The provider route isn't ready.",
  invalid_provider_profile_reference: "The route names a profile that doesn't exist.",
  transport_not_found: "The route's transport is gone.",
  transport_not_active: "The route's transport version isn't active.",
  transport_provider_snapshot_mismatch: "The route's transport no longer matches the provider.",
  transport_runtime_profile_mismatch: "The route's transport profile doesn't match its runtime.",
  transport_runtime_profile_not_materialized: "The route's transport isn't set up yet.",
  direct_transport_not_provider_schedulable:
    "The route uses a direct transport, which the provider can't schedule.",
  contact_link_assignment_not_found: "The route has no link assignment.",
  contact_path_template_not_found: "The route's path template is gone.",
  source_endpoint_not_found: "The route's source endpoint is gone.",
  missing_provider_spacecraft_reference: "These spacecraft have no provider-side ID.",
  missing_downlink_path: "The route has no downlink path set up.",
  spacecraft_not_found: "The spacecraft is gone.",
  no_ready_route: "No route to the provider is ready.",
};

const NORAD_WORDS =
  "Their current element sets carry no NORAD id, so the provider can't look their orbits up.";

const isIn = <T extends string>(list: readonly T[], value: string): value is T =>
  (list as readonly string[]).includes(value);

/**
 * The reason in words for a cause: a known code's sentence, else that it isn't recognized (U20:
 * the code is Cadence's own, so it is shown).
 */
export function ephemerisReasonWords(
  cause: EphemerisCause,
  reason: string | Unrecognized | null,
): string {
  if (cause === "norad_id_missing") return NORAD_WORDS;
  if (reason === null) return "No reason was recorded.";
  const code = isKnown(reason) ? reason : reason.unrecognized;
  if (cause === "failed" && isIn(failedReasons, code)) return failedWords[code];
  if (cause === "not_ready" && isIn(notReadyReasons, code)) return notReadyWords[code];
  return `Reason not recognized (${code}).`;
}

/** The cause after a spacecraft count, for titles: `3 spacecraft without a NORAD id`. */
export const causeWords: Readonly<Record<EphemerisCause, string>> = {
  norad_id_missing: "without a NORAD id",
  failed: "whose orbit upload is failing",
  not_ready: "with no ready route",
};
