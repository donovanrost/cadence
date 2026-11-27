import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  detailsOf,
  isError,
  isKnown,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  type Unrecognized,
} from "@/api";

/**
 * Comms parity 2 (lead 11-16): the choices and preview for a provider-managed transport, readers
 * first. api's read over domain's Management.Transports.derive/3, which the transport kind's
 * validation also calls, so the preview and the stored transport can't disagree.
 *
 * services is empty until a provider is chosen, deliveries until a service is; preview is null until
 * all three are, or when derive refuses (then errors carries its field errors).
 */

const choiceShape = {
  id: d.token,
  version: d.integer,
  // free-text: a provider's or profile's display name, shown as written.
  name: d.string,
};
const choice = d.object(choiceShape);
export type ProviderChoice = Decoded<typeof choice>;

/**
 * #993 (DECISIONS #115): a delivery the listening transport could use but for the provider's
 * egress addresses is listed with `egress_addresses_ready: false`. Absent before #993: ready.
 */
const delivery = d.object({
  ...choiceShape,
  egress_addresses_ready: d.optional(d.boolean),
});
export type DeliveryChoice = Decoded<typeof delivery>;
export const egressReady = (c: DeliveryChoice) => c.egress_addresses_ready !== false;
export const EGRESS_NOT_READY = "the provider hasn't given the addresses it connects from";

/** #993: derive's coded refusals on delivery_profile_ref (setup.md, transport). */
export const egressCodes = [
  "provider_egress_addresses_missing",
  "provider_egress_addresses_too_broad",
  "provider_egress_addresses_invalid",
] as const;
type EgressCode = (typeof egressCodes)[number];
const egressWords: Readonly<Record<EgressCode, string>> = {
  provider_egress_addresses_missing:
    "The provider hasn't given the addresses it connects from in this delivery profile, so Cadence can't listen for it. Ask the provider to add them.",
  provider_egress_addresses_too_broad:
    "This delivery profile's source addresses allow every address, so Cadence can't listen for it. Ask the provider to narrow them.",
  provider_egress_addresses_invalid:
    "This delivery profile's source addresses aren't IP addresses or CIDR ranges, so Cadence can't listen for it. Ask the provider to correct them.",
};
const codeReader = d.optional(d.nullable(d.knownText(egressCodes)));

/** A field error's words: a coded one's own, else derive's sentence as written. */
export function errorWords(
  e: Readonly<{ message: string; code?: EgressCode | Unrecognized | null | undefined }>,
): string {
  return e.code && isKnown(e.code) ? egressWords[e.code] : e.message;
}

/** A refused stage's details (`invalid_op`), read for the delivery's coded egress refusal. */
const stageDetails = d.object({
  errors: d.array(
    d.object({
      /** Only the delivery's path matters here; any other reads as unrecognized. */
      path: d.nullable(d.knownText(["delivery_profile_ref"] as const)),
      // free-text: the kind's refusal sentence, shown as written.
      message: d.string,
      code: codeReader,
    }),
    200,
  ),
});

/** A refused stage's coded egress error on the delivery, in words; null when there's none. */
export function stageEgressRefusal(error: ApiError): string | null {
  if (!isError(error, "invalid_op")) return null;
  const hit = detailsOf(error, stageDetails)?.errors.find(
    (e) => e.path !== null && isKnown(e.path) && e.code && isKnown(e.code),
  );
  return hit ? errorWords(hit) : null;
}

const row = d.object({
  // free-text: api's rendered label for a derived setting, shown as written.
  label: d.string,
  // free-text: the setting's rendered value.
  value: d.string,
});

/** The paths derive refuses on (domain); anything else is a general refusal (path null). */
export const providerErrorPaths = [
  "mission_provider_id",
  "mission_provider_version",
  "service_profile_ref",
  "delivery_profile_ref",
] as const;
export type ProviderErrorPath = (typeof providerErrorPaths)[number];

export const providerOptionsReader = d.object({
  providers: d.array(choice, 200),
  services: d.array(choice, 200),
  deliveries: d.array(delivery, 200),
  preview: d.nullable(
    d.object({
      configuration: d.array(row, 64),
      direction_capability: d.knownText(["inbound", "outbound", "bidirectional"] as const),
      provider_version: d.integer,
      summary: d.array(row, 16),
    }),
  ),
  errors: d.array(
    d.object({
      path: d.nullable(d.knownText(providerErrorPaths)),
      // free-text: derive's refusal sentence, shown as written.
      message: d.string,
      /** #993: additive; the egress refusals carry one (worded by errorWords). */
      code: codeReader,
    }),
    32,
  ),
});
export type ProviderOptions = Decoded<typeof providerOptionsReader>;

export type ProviderSelection = Readonly<{
  providerId: string | null;
  serviceProfileId: string | null;
  deliveryProfileId: string | null;
}>;

export function fetchProviderOptions(
  key: Readonly<{ missionId: MissionId } & ProviderSelection>,
  signal?: AbortSignal,
): Promise<ApiResult<ProviderOptions>> {
  const query = new URLSearchParams();
  if (key.providerId) query.set("provider_id", key.providerId);
  if (key.serviceProfileId) query.set("service_profile_id", key.serviceProfileId);
  if (key.deliveryProfileId) query.set("delivery_profile_id", key.deliveryProfileId);
  const q = query.toString();
  return request(
    `/missions/${encodeURIComponent(key.missionId)}/config/kinds/transport/provider-options${q ? `?${q}` : ""}`,
    providerOptionsReader,
    signal ? { signal } : {},
  );
}
