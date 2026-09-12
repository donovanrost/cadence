import { boolean, choice, invalid, record, text } from "../../shared/read-validation.ts";
import { array, object, unique } from "../../shared/form-validation.ts";
import type { FormInput } from "../../shared/form-workflow.contracts.ts";
import type { Detail, Option } from "./transport-new.contracts.ts";
export type ProviderSetup = {
  kind: string;
  providerId: string;
  providerVersion: string;
  serviceId: string;
  deliveryId: string;
  providerName: string | null;
  services: Option[];
  deliveries: Option[];
  configuration: Detail[];
};
export type TransportReview = {
  valid: boolean;
  origin: "direct" | "provider_managed";
  endpoint: string | null;
  setup: ProviderSetup | null;
};
export function admitValidation(receipt: unknown, input?: FormInput): TransportReview {
  const envelope = record(receipt),
    result = record(envelope.result ?? envelope);
  const valid = boolean(result.valid);
  const review = record(result.transport_review);
  const origin = choice(review.origin, ["direct", "provider_managed"]);
  if (input && input.transport?.origin !== origin) return invalid();
  if (origin === "direct") {
    if (!valid) return invalid();
    return { valid, origin, endpoint: text(review.endpoint), setup: null };
  }
  const source = record(result.provider_setup);
  if (source.version !== 1 || !input?.transport) return invalid();
  const draft = input.transport;
  for (const [field, key] of [
    ["transport_kind", "transport_kind"],
    ["provider_id", "mission_provider_id"],
    ["provider_version", "mission_provider_version"],
    ["service_profile_id", "service_profile_id"],
    ["delivery_profile_id", "delivery_profile_id"],
  ])
    if (text(source[field], true, 240) !== (draft[key] ?? "")) return invalid();
  const options = array(
    object({
      label: (value) => text(value, false, 240),
      value: (value) => text(value, false, 240),
      disabled: boolean,
    }),
    100,
  );
  const services = options(source.services),
    deliveries = options(source.deliveries);
  unique(services.map((option) => option.value));
  unique(deliveries.map((option) => option.value));
  const setup: ProviderSetup = {
    kind: draft.transport_kind,
    providerId: draft.mission_provider_id ?? "",
    providerVersion: draft.mission_provider_version ?? "",
    serviceId: draft.service_profile_id ?? "",
    deliveryId: draft.delivery_profile_id ?? "",
    providerName: source.provider_name === null ? null : text(source.provider_name, false, 240),
    services,
    deliveries,
    configuration: array(
      object({
        label: (value) =>
          choice(value, [
            "Endpoint",
            "Mode",
            "Direction",
            "Framing",
            "Frame bytes",
            "Reconnect",
            "TLS",
          ]),
        value: (value) => text(value, false, 240),
        mono: boolean,
      }),
      7,
    )(source.configuration),
  };
  unique(setup.configuration.map((row) => row.label));
  const endpoint = review.endpoint === null ? null : text(review.endpoint, false, 240);
  if (
    setup.providerId
      ? !setup.providerName || !/^[1-9][0-9]*$/.test(setup.providerVersion)
      : setup.providerName !== null || setup.providerVersion !== "" || services.length !== 0
  )
    return invalid();
  if (
    setup.serviceId
      ? !services.some((option) => !option.disabled && option.value === setup.serviceId)
      : deliveries.length !== 0
  )
    return invalid();
  if (
    setup.deliveryId &&
    !deliveries.some((option) => !option.disabled && option.value === setup.deliveryId)
  )
    return invalid();
  if (
    endpoint !== null &&
    (!setup.deliveryId ||
      setup.configuration.length !== 7 ||
      setup.configuration.find((row) => row.label === "Endpoint")?.value !== endpoint)
  )
    return invalid();
  if (endpoint === null && setup.configuration.length !== 0) return invalid();
  if (
    valid &&
    (!setup.providerId ||
      !setup.serviceId ||
      !setup.deliveryId ||
      !endpoint ||
      !draft.display_name?.trim())
  )
    return invalid();
  return { valid, origin, endpoint, setup };
}
