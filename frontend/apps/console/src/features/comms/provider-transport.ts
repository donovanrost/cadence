import type { StageOp } from "@/features/changes/index.ts";
import type { ProviderChoice, ProviderOptions } from "./provider-options.ts";

/**
 * A provider-managed transport through the change set (comms parity 2; domain's document shape):
 * the console stages origin, name, the provider with its version, and the service and delivery
 * profiles as exact {id, version} refs. Configuration and direction are derived by the kind (the
 * same derive/3 the preview shows), so they're never staged.
 */

export type ProviderForm = Readonly<{
  name: string;
  providerId: string;
  serviceId: string;
  deliveryId: string;
}>;

type Doc = Readonly<Record<string, unknown>>;

const text = (doc: Doc, key: string) => {
  const v = doc[key];
  return typeof v === "string" ? v : "";
};
const refId = (doc: Doc, key: string) => {
  const v = doc[key];
  if (typeof v !== "object" || v === null || !("id" in v)) return "";
  return typeof v.id === "string" ? v.id : "";
};

/** The form's starting values: a stored provider-managed transport's, or empty for a new one. */
export function formFromDocument(doc: Doc): ProviderForm {
  return {
    name: text(doc, "display_name"),
    providerId: text(doc, "mission_provider_id"),
    serviceId: refId(doc, "service_profile_ref"),
    deliveryId: refId(doc, "delivery_profile_ref"),
  };
}

const pick = (list: readonly ProviderChoice[], id: string) => list.find((c) => c.id === id) ?? null;

/** Why the form can't stage yet, in words; null when it can. */
export function blockedReason(form: ProviderForm, options: ProviderOptions | null): string | null {
  if (form.name.trim() === "") return "Give the transport a name.";
  if (!form.providerId || !form.serviceId || !form.deliveryId)
    return "Choose a provider, a service and a delivery profile.";
  if (!options?.preview) return "Fix the provider choices first.";
  return null;
}

/** The staged document (create) or the changed paths (update); null if the choices aren't on offer. */
export function providerOp(
  entityId: string | null,
  stored: Doc,
  form: ProviderForm,
  options: ProviderOptions,
): StageOp | null {
  const provider = pick(options.providers, form.providerId);
  const service = pick(options.services, form.serviceId);
  const delivery = pick(options.deliveries, form.deliveryId);
  if (!provider || !service || !delivery) return null;
  // keyed-by-text: the change-set document's field paths (a JSON body for the kind), not a word map.
  const document: Readonly<Record<string, unknown>> = {
    origin: "provider_managed",
    display_name: form.name.trim(),
    mission_provider_id: provider.id,
    mission_provider_version: provider.version,
    service_profile_ref: { id: service.id, version: service.version },
    delivery_profile_ref: { id: delivery.id, version: delivery.version },
  };
  if (entityId === null) return { kind: "transport", action: "create", document };
  const changes = Object.entries(document)
    .filter(([path, value]) => JSON.stringify(stored[path]) !== JSON.stringify(value))
    .map(([path, value]) => ({ path, value }));
  return { kind: "transport", action: "update", entity_id: entityId, changes };
}
