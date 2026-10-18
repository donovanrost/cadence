import { producerFixture } from "../../../../../../test-support/producer-fixture";
import { jsonFixture, fixtureRecord } from "../../../../../../test-support/json-fixture";
import { required } from "../../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { expect, test, vi } from "vite-plus/test";
import AdministrationPage from "../../AdministrationPage.vue";
import OrganizationHomePanel from "./OrganizationHomePanel.vue";
import { readOrganizationHome } from "./contracts";
const fixture = () => ({
  version: 1,
  organization: { id: "org-a", name: "Flight operations", slug: "flight" },
  counts: { missions: 26, spacecraft: 120, active_memberships: 4 },
  recent_missions: [
    {
      id: "mission-z",
      name: "Newest mission",
      slug: "z-last-alphabetically",
      created_at: "2026-09-09T12:00:00.000001Z",
    },
    {
      id: "mission-a",
      name: "Older mission",
      slug: "a-first-alphabetically",
      created_at: "2026-09-08T12:00:00.000000Z",
    },
  ],
});
test("scoped totals and producer-ordered recent missions have canonical links without readiness claims", () => {
  const wrapper = mount(pageHeaderHarness("/").stage(OrganizationHomePanel), {
    props: { model: readOrganizationHome(fixture(), "org-a") },
  });
  expect(wrapper.get("#organization-stat-missions").text()).toContain("26");
  expect(wrapper.get("#organization-stat-spacecraft").text()).toContain("120");
  expect(wrapper.get("#organization-stat-members").text()).toContain("4");
  expect(wrapper.findAll("li a").map((a) => a.attributes("href"))).toEqual([
    "/missions/mission-z",
    "/missions/mission-a",
  ]);
  expect(wrapper.get("#organization-new-mission").attributes("href")).toBe("/missions/new");
  expect(wrapper.get("#organization-all-missions").attributes("href")).toBe("/missions");
  expect(wrapper.text()).not.toContain("Ready");
  wrapper.unmount();
});
test("empty organization keeps a reachable mission creation action", () => {
  const doc = fixture();
  doc.counts.missions = 0;
  doc.counts.spacecraft = 0;
  doc.recent_missions = [];
  const wrapper = mount(pageHeaderHarness("/").stage(OrganizationHomePanel), {
    props: { model: readOrganizationHome(doc, "org-a") },
  });
  expect(wrapper.find("#organization-missions-empty").exists()).toBe(true);
  expect(wrapper.get("#organization-new-mission").attributes("href")).toBe("/missions/new");
  wrapper.unmount();
});
test("invalid context, forged identities, overfull and duplicate rows cannot become home content", () => {
  expect(() => readOrganizationHome(fixture(), "org-other")).toThrow();
  const mutations: ((doc: ReturnType<typeof fixture>) => void)[] = [
    (d) => {
      d.version = 2;
    },
    (d) => {
      d.counts.missions = -1;
    },
    (d) => {
      required(d.recent_missions[0]).id = "../../foreign";
    },
    (d) => {
      d.recent_missions.push(...d.recent_missions);
    },
    (d) => {
      required(d.recent_missions[1]).id = required(d.recent_missions[0]).id;
    },
    (d) => {
      required(d.recent_missions[0]).created_at = "not-a-date";
    },
  ];
  for (const mutate of mutations) {
    const doc = fixture();
    mutate(doc);
    expect(() => readOrganizationHome(doc, "org-a")).toThrow();
  }
});
test("host contains unavailable or mismatched snapshots, retries and admits a recovered organization", async () => {
  const refresh = vi.fn(async () => {});
  const ready = {
    version: 1,
    page: "organization_home",
    status: "ready",
    organization_id: "org-a",
    data: fixture(),
  };
  const wrapper = mount(AdministrationPage, {
    props: { page: "organization_home", organizationId: "org-a", snapshot: null, refresh },
  });
  for (const snapshot of [
    null,
    {},
    { ...ready, status: "unavailable" },
    { ...ready, organization_id: "org-b" },
    { ...ready, data: {} },
  ]) {
    await wrapper.setProps({ snapshot });
    expect(wrapper.find("#core-administration-error").exists()).toBe(true);
    expect(wrapper.find("#organization-home-page").exists()).toBe(false);
  }
  await wrapper.get("#core-administration-retry").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  await wrapper.setProps({ snapshot: ready });
  expect(wrapper.find("#organization-home-page").exists()).toBe(true);
  await wrapper.setProps({ organizationId: "org-b" });
  expect(wrapper.find("#organization-home-page").exists()).toBe(false);
  wrapper.unmount();
});

const producer = producerFixture("CADENCE_ORGANIZATION_HOME_DOCUMENT", import.meta.url);
test.skipIf(!producer.available)("actual producer document reaches the core home feature", () => {
  const encoded = producer.read();
  const data = jsonFixture(encoded);
  const model = readOrganizationHome(data, fixtureRecord(data.organization).id);
  const wrapper = mount(pageHeaderHarness("/").stage(OrganizationHomePanel), { props: { model } });
  expect(wrapper.findAll("li a").map((a) => a.attributes("href"))).toEqual(
    model.recent_missions.map((m) => `/missions/${encodeURIComponent(m.id)}`),
  );
  expect(wrapper.get("#organization-stat-missions").text()).toContain(
    String(model.counts.missions),
  );
  expect(wrapper.findAll("time").map((t) => t.attributes("datetime"))).toEqual(
    model.recent_missions.map((m) => m.created_at),
  );
  wrapper.unmount();
});
