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

/** A full selection whose preview says whether the delivery listens for downlink (#202). */
const chosen = (eligible: boolean) => ({
  ...options,
  preview: {
    configuration: [{ label: "Endpoint", value: "127.0.0.1:5100" }],
    direction_capability: eligible ? "inbound" : "bidirectional",
    listener_eligible: eligible,
    provider_version: 3,
    summary: [{ label: "Endpoint", value: "127.0.0.1:5100" }],
  },
});

async function mountChosen(eligible: boolean, configuration: Record<string, unknown>) {
  vi.stubGlobal(
    "fetch",
    vi.fn(() =>
      Promise.resolve(new Response(JSON.stringify({ data: chosen(eligible) }), { status: 200 })),
    ),
  );
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: "/", name: "home", component: { template: "<div />" } }],
  });
  const w = mount(ProviderTransportForm, {
    props: {
      missionId: missionId("m-1"),
      entityId: "tr_1",
      document: {
        origin: "provider_managed",
        display_name: "Northlight S-band",
        mission_provider_id: "prov_n",
        mission_provider_version: 3,
        service_profile_ref: { id: "svc_s", version: 2 },
        delivery_profile_ref: { id: "dlv_ok", version: 5 },
        configuration,
      },
      done: { name: "home" },
    },
    global: { plugins: [router] },
  });
  await flushPromises();
  return w;
}

describe("ProviderTransportForm Listener (#202)", () => {
  it("offers Own or Shared for a listening downlink, prefilled from the stored choice", async () => {
    const w = await mountChosen(true, { listener: "shared" });
    const selects = w.findAll("select");
    expect(selects).toHaveLength(4);
    const listener = selects[3];
    expect((listener?.element as HTMLSelectElement | undefined)?.value).toBe("shared");
    expect(listener?.findAll("option").map((o) => o.text())).toEqual([
      "Own listener for each pass",
      "Shared, routed by SCID",
    ]);
    expect(w.text()).not.toContain("will stop sharing its listener");
    w.unmount();
  });

  it("hides the choice when the delivery can't share, and says a stored Shared stops", async () => {
    const w = await mountChosen(false, { listener: "shared" });
    expect(w.findAll("select")).toHaveLength(3);
    expect(w.text()).toContain(
      "This transport will stop sharing its listener: only a downlink transport that listens can share one.",
    );
    w.unmount();
  });

  it("says nothing about sharing for an Own transport that can't share", async () => {
    const w = await mountChosen(false, {});
    expect(w.findAll("select")).toHaveLength(3);
    expect(w.text()).not.toContain("will stop sharing its listener");
    w.unmount();
  });
});
