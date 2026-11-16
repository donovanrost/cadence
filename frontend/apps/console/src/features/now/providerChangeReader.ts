import { decoders as d, type Decoded } from "@/api/index.ts";

/** Provider-change fields (ProviderReservationChanges' document keys); values are JSON text. */
export const changeFields = [
  "starts_at",
  "ends_at",
  "ground_station_ref",
  "antenna_or_service_pool_ref",
  "service_profile_ref",
  "delivery_profile_ref",
  "spacecraft_ref",
  "pass_phase",
  "status",
] as const;
const providerChangeFields = {
  id: d.token,
  classification: d.knownText([
    "approval_required",
    "acknowledgment_required",
    "configuration_failure",
    "policy_accept",
  ] as const),
  // Domain's lifecycle plus expired (api, L14 flown passes); an unknown one reads as evidence only.
  state: d.knownText([
    "pending_approval",
    "acknowledgment_required",
    "configuration_failure",
    "expired",
    "approved",
    "rejected",
    "acknowledged",
    "superseded",
    "policy_accepted",
    "observed",
    "apply_failed",
  ] as const),
  deadline_at: d.nullable(d.timestamp),
  provider_revision: d.nullable(d.integer),
  // The decision's guard, sent back verbatim with approve / reject / acknowledge.
  proposal_hash: d.string,
  already_effective: d.boolean,
  fields: d.array(
    d.object({
      field: d.knownText(changeFields),
      // free-text: a server label for the field when it has one (null today)
      label: d.nullable(d.string),
      before_json: d.nullable(d.string),
      after_json: d.nullable(d.string),
    }),
    50,
  ),
} as const;
export const providerChangeReader = d.object(providerChangeFields);

export type ProviderChange = Decoded<typeof providerChangeReader>;
/** GET /passes/:id provider_changes[] (api, L14 flown passes): the change plus when it was raised. */
export const passChangeReader = d.object({
  ...providerChangeFields,
  raised_at: d.timestamp,
  resolution: d.nullable(
    d.object({
      // free-text: the decision's own key; the state carries the outcome (ux U44)
      action: d.string,
      by: d.nullable(d.object({ id: d.nullable(d.token), name: d.nullable(d.string) })),
      at: d.timestamp,
      // free-text: the decider's reason
      reason: d.nullable(d.string),
    }),
  ),
});
export type PassChange = Decoded<typeof passChangeReader>;
