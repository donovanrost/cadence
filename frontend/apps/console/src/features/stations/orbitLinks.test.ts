import { flushPromises, mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { decode, missionId } from "@/api";
import { providerReader } from "./api.ts";
import ProviderDetail from "./ProviderDetail.vue";
import ProvidersTable from "./ProvidersTable.vue";

/** Synthetic fixture in setup.md's providers row shape (#982, #987), not captured from a server. */
const provider = () => {
  const r = decode(providerReader, {
    id: "prov_1",
    name: "Northlight",
    provider_type: "reflect_orbital",
    account: { id: "acc_1", name: "Northlight prod" },
    status: { lifecycle_state: "active", last_validated_at: null, last_synced_at: null },
    station_count: 4,
    version: 2,
    policy_mode: "approval_required",
    grant: { id: "g1", version: 3, state: "active" },
    health: {
      validate: { status: null, checked_at: null, error: null },
      sync: { status: null, checked_at: null, error: null },
    },
    ephemeris: {
      orbit_source: "accepts_ephemeris_upload",
      uploaded: 4,
      failed: 1,
      not_ready: 2,
      pending: 1,
      lookup: 0,
      norad_id_missing: 1,
    },
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};
const causeOf = (to: unknown) =>
  (to as { query?: { cause?: string } }).query?.cause ?? "(no cause)";

describe("Orbits count links: the detail only (CLAUDE.md rule 9)", () => {
  it("the Providers table's only link per row is the Name cell", () => {
    const w = mount(ProvidersTable, {
      props: { providers: [provider()] },
      global: { stubs: { RouterLink: RouterLinkStub } },
    });
    const links = w.findAllComponents(RouterLinkStub);
    expect(links.map((l) => l.text())).toEqual(["Northlight"]);
    expect(w.find('[data-bucket="failed"]').exists()).toBe(true);
    w.unmount();
  });

  it("the provider's detail links its three caution counts by cause", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: "/providers/:providerId?",
          name: "setup.stations.providers",
          component: { template: "<div />" },
        },
      ],
    });
    await router.push("/providers/prov_1");
    const w = mount(ProviderDetail, {
      props: { missionId: missionId("m-1"), provider: provider(), canManage: false },
      global: { plugins: [router], stubs: { RouterLink: RouterLinkStub } },
    });
    await flushPromises();
    const links = w.findAllComponents(RouterLinkStub);
    expect(links.map((l) => causeOf(l.props("to")))).toEqual([
      "failed",
      "norad_id_missing",
      "not_ready",
    ]);
    w.unmount();
  });
});
