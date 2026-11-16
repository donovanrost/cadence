import type { MissionId } from "@/api/index.ts";
import { decoders as d, request, type ApiResult, type Decoded } from "@/api";

/**
 * Comms parity 2 (lead 11-16): the choices and preview for a provider-managed transport, readers
 * first. api's read over domain's Management.Transports.derive/3, which the transport kind's
 * validation also calls, so the preview and the stored transport can't disagree.
 *
 * services is empty until a provider is chosen, deliveries until a service is; preview is null until
 * all three are, or when derive refuses (then errors carries its field errors).
 */

const choice = d.object({
  id: d.token,
  version: d.integer,
  // free-text: a provider's or profile's display name, shown as written.
  name: d.string,
});
export type ProviderChoice = Decoded<typeof choice>;

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

export const providerOptionsReader = d.object({
  providers: d.array(choice, 200),
  services: d.array(choice, 200),
  deliveries: d.array(choice, 200),
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
