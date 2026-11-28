import { describe, expect, it } from "vite-plus/test";
import type { ProviderOptions } from "./provider-options.ts";
import { blockedReason, formFromDocument, providerOp } from "./provider-transport.ts";

const options: ProviderOptions = {
  providers: [{ id: "prov_n", version: 3, name: "Northlight" }],
  services: [{ id: "svc_s", version: 2, name: "S-band" }],
  deliveries: [{ id: "dlv_t", version: 5, name: "TCP to Cadence", egress_addresses_ready: true }],
  preview: {
    configuration: [{ label: "Endpoint", value: "gs.example:7000" }],
    direction_capability: "inbound",
    listener_eligible: true,
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
  listener: "own" as const,
};
const closedPreview = (o: ProviderOptions): ProviderOptions =>
  o.preview ? { ...o, preview: { ...o.preview, listener_eligible: false } } : o;

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

  it("carries the Listener only when it shares on create (#202)", () => {
    const shared = providerOp(null, {}, { ...form, listener: "shared" }, options);
    expect(shared).toMatchObject({
      action: "create",
      document: { configuration: { listener: "shared" } },
    });
    const own = providerOp(null, {}, form, options);
    expect(own && "document" in own ? own.document : null).not.toHaveProperty("configuration");
    // A delivery that doesn't listen for downlink can't share, whatever the form says.
    const closed = providerOp(null, {}, { ...form, listener: "shared" }, closedPreview(options));
    expect(closed && "document" in closed ? closed.document : null).not.toHaveProperty(
      "configuration",
    );
  });

  it("stages the Listener path on edit, and Own over a missing key is no change", () => {
    const stored = {
      origin: "provider_managed",
      display_name: "North S-band",
      mission_provider_id: "prov_n",
      mission_provider_version: 3,
      service_profile_ref: { id: "svc_s", version: 2 },
      delivery_profile_ref: { id: "dlv_t", version: 5 },
      configuration: { host: "gs.example" },
    };
    expect(providerOp("tr_1", stored, form, options)).toMatchObject({ changes: [] });
    expect(providerOp("tr_1", stored, { ...form, listener: "shared" }, options)).toMatchObject({
      changes: [{ path: "configuration.listener", value: "shared" }],
    });
    const sharing = { ...stored, configuration: { host: "gs.example", listener: "shared" } };
    expect(formFromDocument(sharing).listener).toBe("shared");
    expect(providerOp("tr_1", sharing, { ...form, listener: "shared" }, options)).toMatchObject({
      changes: [],
    });
    // U83: the delivery no longer listens for downlink, so the stored Shared goes back to Own.
    expect(
      providerOp("tr_1", sharing, { ...form, listener: "shared" }, closedPreview(options)),
    ).toMatchObject({ changes: [{ path: "configuration.listener", value: "own" }] });
  });
});
