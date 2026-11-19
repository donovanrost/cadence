import { describe, expect, it } from "vite-plus/test";
import { decode, isKnown } from "@/api";
import { providerOptionsReader } from "./provider-options.ts";

/** api's agreed shape (comms parity 2): exact refs carry versions; preview and errors per derive/3. */
const chosen = {
  providers: [{ id: "provider_north", version: 3, name: "Northlight" }],
  services: [{ id: "svc_s_band", version: 2, name: "S-band contacts" }],
  deliveries: [{ id: "dlv_tcp", version: 5, name: "TCP to Cadence" }],
  preview: {
    configuration: [
      { label: "Host", value: "gs.northlight.example" },
      { label: "Port", value: "7000" },
    ],
    direction_capability: "inbound",
    provider_version: 3,
    summary: [{ label: "Endpoint", value: "gs.northlight.example:7000" }],
  },
  errors: [],
};

describe("provider-options reader", () => {
  it("reads a full selection with its preview", () => {
    const r = decode(providerOptionsReader, chosen);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.value.deliveries[0]).toEqual({ id: "dlv_tcp", version: 5, name: "TCP to Cadence" });
    expect(r.value.preview?.summary).toEqual([
      { label: "Endpoint", value: "gs.northlight.example:7000" },
    ]);
  });

  it("reads derive's refusals: a known field path, or null for a general one", () => {
    const r = decode(providerOptionsReader, {
      ...chosen,
      preview: null,
      errors: [
        { path: "delivery_profile_ref", message: "This delivery doesn't support the service." },
        { path: null, message: "The provider's control plane is unhealthy." },
      ],
    });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const [field, general] = r.value.errors;
    expect(field?.path !== null && field?.path !== undefined && isKnown(field.path)).toBe(true);
    expect(general?.path).toBeNull();
  });

  it("reads an unchosen state: empty choices downstream and no preview", () => {
    const r = decode(providerOptionsReader, {
      ...chosen,
      services: [],
      deliveries: [],
      preview: null,
    });
    expect(r.ok && r.value.services).toEqual([]);
  });
});
