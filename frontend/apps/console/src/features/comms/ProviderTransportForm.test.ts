import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api";
import ProviderTransportForm from "./ProviderTransportForm.vue";

afterEach(() => vi.unstubAllGlobals());

/** Synthetic provider-options answer in changes.md's shape with #993's egress flag. */
const options = {
  providers: [{ id: "prov_n", version: 3, name: "Northlight" }],
  services: [{ id: "svc_s", version: 2, name: "S-band" }],
  deliveries: [
    { id: "dlv_ok", version: 5, name: "TCP to Cadence", egress_addresses_ready: true },
    { id: "dlv_no", version: 1, name: "Relay", egress_addresses_ready: false },
  ],
  preview: null,
  errors: [],
};

describe("ProviderTransportForm deliveries (#993)", () => {
  it("keeps a delivery without egress addresses visible but disabled, saying why", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() =>
        Promise.resolve(new Response(JSON.stringify({ data: options }), { status: 200 })),
      ),
    );
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: "/", name: "home", component: { template: "<div />" } }],
    });
    const w = mount(ProviderTransportForm, {
      props: {
        missionId: missionId("m-1"),
        entityId: null,
        document: {
          display_name: "Northlight S-band",
          mission_provider_id: "prov_n",
          service_profile_ref: { id: "svc_s", version: 2 },
        },
        done: { name: "home" },
      },
      global: { plugins: [router] },
    });
    await flushPromises();
    const delivery = w.findAll("select")[2];
    const opts = (delivery?.findAll("option") ?? []).filter((o) => o.attributes("value"));
    expect(opts.map((o) => [o.text(), o.attributes("disabled") !== undefined])).toEqual([
      ["TCP to Cadence", false],
      ["Relay (the provider hasn't given the addresses it connects from)", true],
    ]);
    w.unmount();
  });
});
