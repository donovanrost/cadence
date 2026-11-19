import { describe, expect, it } from "vite-plus/test";
import type { ProviderOptions } from "./provider-options.ts";
import { blockedReason, formFromDocument, providerOp } from "./provider-transport.ts";

const options: ProviderOptions = {
  providers: [{ id: "prov_n", version: 3, name: "Northlight" }],
  services: [{ id: "svc_s", version: 2, name: "S-band" }],
  deliveries: [{ id: "dlv_t", version: 5, name: "TCP to Cadence" }],
  preview: {
    configuration: [{ label: "Endpoint", value: "gs.example:7000" }],
    direction_capability: "inbound",
    provider_version: 3,
    summary: [{ label: "Endpoint", value: "gs.example:7000" }],
  },
  errors: [],
};
const form = {
  name: "North S-band",
  providerId: "prov_n",
  serviceId: "svc_s",
  deliveryId: "dlv_t",
};

describe("provider-managed transport ops (comms parity 2)", () => {
  it("creates with exact versioned refs and never stages derived settings", () => {
    expect(providerOp(null, {}, form, options)).toEqual({
      kind: "transport",
      action: "create",
      document: {
        origin: "provider_managed",
        display_name: "North S-band",
        mission_provider_id: "prov_n",
        mission_provider_version: 3,
        service_profile_ref: { id: "svc_s", version: 2 },
        delivery_profile_ref: { id: "dlv_t", version: 5 },
      },
    });
  });

  it("updates only the paths that changed, prefilled from the stored document", () => {
    const stored = {
      origin: "provider_managed",
      display_name: "North S-band",
      mission_provider_id: "prov_n",
      mission_provider_version: 3,
      service_profile_ref: { id: "svc_s", version: 2 },
      delivery_profile_ref: { id: "dlv_t", version: 4 },
      configuration: { host: "old" },
    };
    expect(formFromDocument(stored)).toEqual(form);
    expect(providerOp("tr_1", stored, form, options)).toEqual({
      kind: "transport",
      action: "update",
      entity_id: "tr_1",
      changes: [{ path: "delivery_profile_ref", value: { id: "dlv_t", version: 5 } }],
    });
  });

  it("says what blocks staging, and refuses choices no longer on offer", () => {
    expect(blockedReason({ ...form, name: " " }, options)).toBe("Give the transport a name.");
    expect(blockedReason({ ...form, deliveryId: "" }, options)).toBe(
      "Choose a provider, a service and a delivery profile.",
    );
    expect(blockedReason(form, { ...options, preview: null })).toBe(
      "Fix the provider choices first.",
    );
    expect(blockedReason(form, options)).toBeNull();
    expect(providerOp(null, {}, { ...form, serviceId: "gone" }, options)).toBeNull();
  });
});
