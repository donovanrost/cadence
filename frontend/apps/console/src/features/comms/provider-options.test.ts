import { describe, expect, it } from "vite-plus/test";
import { decode, isKnown, type ApiError } from "@/api";
import {
  egressReady,
  errorWords,
  providerOptionsReader,
  stageEgressRefusal,
} from "./provider-options.ts";

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

describe("egress addresses (#993, DECISIONS #115)", () => {
  it("reads each delivery's egress_addresses_ready; absent (before #993) is ready", () => {
    const r = decode(providerOptionsReader, {
      ...chosen,
      deliveries: [
        { id: "dlv_a", version: 1, name: "Ready", egress_addresses_ready: true },
        { id: "dlv_b", version: 1, name: "Not ready", egress_addresses_ready: false },
        { id: "dlv_c", version: 1, name: "Older server" },
      ],
    });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    expect(r.value.deliveries.map(egressReady)).toEqual([true, false, true]);
  });

  it("words the three coded refusals; an unknown or absent code keeps derive's sentence", () => {
    const r = decode(providerOptionsReader, {
      ...chosen,
      preview: null,
      errors: [
        { path: "delivery_profile_ref", message: "srv", code: "provider_egress_addresses_missing" },
        {
          path: "delivery_profile_ref",
          message: "srv",
          code: "provider_egress_addresses_too_broad",
        },
        { path: "delivery_profile_ref", message: "srv", code: "provider_egress_addresses_invalid" },
        { path: "delivery_profile_ref", message: "Server's own words.", code: "something_new" },
        { path: "service_profile_ref", message: "That service profile isn't active." },
      ],
    });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    expect(r.value.errors.map(errorWords)).toEqual([
      "The provider hasn't given the addresses it connects from in this delivery profile, so Cadence can't listen for it. Ask the provider to add them.",
      "This delivery profile's source addresses allow every address, so Cadence can't listen for it. Ask the provider to narrow them.",
      "This delivery profile's source addresses aren't IP addresses or CIDR ranges, so Cadence can't listen for it. Ask the provider to correct them.",
      "Server's own words.",
      "That service profile isn't active.",
    ]);
  });

  it("finds a refused stage's coded egress error on the delivery", () => {
    const refused = (errors: unknown[]): ApiError => ({
      kind: "invalid",
      code: "invalid_op",
      message: "A staged change is invalid.",
      details: { index: 0, errors },
    });
    expect(
      stageEgressRefusal(
        refused([
          { path: "display_name", message: "Name it." },
          {
            path: "delivery_profile_ref",
            message: "srv",
            code: "provider_egress_addresses_too_broad",
          },
        ]),
      ),
    ).toBe(
      "This delivery profile's source addresses allow every address, so Cadence can't listen for it. Ask the provider to narrow them.",
    );
    expect(stageEgressRefusal(refused([{ path: "delivery_profile_ref", message: "srv" }]))).toBe(
      null,
    );
    expect(stageEgressRefusal({ kind: "not_found", code: "x", message: "" })).toBeNull();
  });
});
