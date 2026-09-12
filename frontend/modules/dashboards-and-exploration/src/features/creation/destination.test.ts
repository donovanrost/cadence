import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CreationDestination from "./CreationDestination.vue";

const fixture = () => ({
  version: 1,
  context: { organization_id: "org-1", mission_id: "mission-1" },
  mode: "new",
  source_dashboard_id: null as string | null,
});
const props = (model: unknown = fixture()) => ({
  model,
  organizationId: "org-1",
  missionId: "mission-1",
});

test.each(["new", "clone", "import"])(
  "preserves %s creation through the canonical owner",
  (mode) => {
    const model = {
      ...fixture(),
      mode,
      source_dashboard_id: mode === "clone" ? "source /?&+" : null,
    };
    const wrapper = mount(CreationDestination, { props: props(model) });
    const url = new URL(wrapper.get("a").attributes("href")!, "https://cadence.test");
    expect(url.pathname).toBe("/missions/mission-1/ops/dashboards/new");
    expect(url.searchParams.get("mode") ?? "new").toBe(mode);
    expect(url.searchParams.get("source_dashboard_id")).toBe(model.source_dashboard_id);
    expect(wrapper.findAll("form")).toHaveLength(0);
    expect(wrapper.emitted("save")).toBeUndefined();
    wrapper.unmount();
  },
);

test.each([
  null,
  {},
  { ...fixture(), version: 2 },
  { ...fixture(), mode: "other" },
  { ...fixture(), mode: "clone" },
  { ...fixture(), mode: "clone", source_dashboard_id: "" },
  { ...fixture(), mode: "clone", source_dashboard_id: "x".repeat(257) },
  { ...fixture(), mode: "clone", source_dashboard_id: "bad\nsource" },
  { ...fixture(), source_dashboard_id: "unexpected" },
  { ...fixture(), context: { organization_id: "foreign", mission_id: "mission-1" } },
  { ...fixture(), context: { organization_id: "org-1", mission_id: "foreign" } },
])("contains unavailable and mismatched data without an actionable destination: %j", (model) => {
  const wrapper = mount(CreationDestination, { props: props(model) });
  expect(wrapper.find("[role=status]").exists()).toBe(true);
  expect(wrapper.findAll("a")).toHaveLength(0);
  wrapper.unmount();
});

test("a host identity change immediately removes the old destination", async () => {
  const wrapper = mount(CreationDestination, { props: props() });
  await wrapper.setProps({ missionId: "mission-2" });
  expect(wrapper.findAll("a")).toHaveLength(0);
  await wrapper.setProps({
    model: { ...fixture(), context: { organization_id: "org-1", mission_id: "mission-2" } },
  });
  expect(wrapper.get("a").attributes("href")).toBe("/missions/mission-2/ops/dashboards/new");
  await wrapper.setProps({ organizationId: "foreign" });
  expect(wrapper.findAll("a")).toHaveLength(0);
  wrapper.unmount();
});

test("actual producer models mount without accepting server supplied destinations", () => {
  const models = process.env.CADENCE_CREATION_DESTINATIONS
    ? JSON.parse(process.env.CADENCE_CREATION_DESTINATIONS)
    : [fixture()];
  for (const model of models) {
    const wrapper = mount(CreationDestination, {
      props: {
        model: { ...model, href: "https://foreign.test", query: { redirect: "//foreign.test" } },
        organizationId: model.context.organization_id,
        missionId: model.context.mission_id,
      },
    });
    const url = new URL(
      wrapper.get("#dashboard-creation-destination-open").attributes("href")!,
      "https://cadence.test",
    );
    expect(url.origin).toBe("https://cadence.test");
    expect(url.pathname).toBe(
      `/missions/${encodeURIComponent(model.context.mission_id)}/ops/dashboards/new`,
    );
    expect(url.searchParams.get("mode") ?? "new").toBe(model.mode);
    expect(url.searchParams.get("source_dashboard_id")).toBe(model.source_dashboard_id);
    expect(url.searchParams.has("redirect")).toBe(false);
    wrapper.unmount();
  }
});
