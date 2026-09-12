import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import WorkspaceLanding from "./WorkspaceLanding.vue";
import { readWorkspaceLanding } from "./contracts";
import { opsNavigation } from "../frame/navigation";

const fixture = () => ({
  version: 1,
  context: { organization_id: "org-1", mission_id: "mission-1" },
  mission_name: "Firebird",
  can_administer: false,
});
const props = (model: unknown = fixture()) => ({
  model,
  organizationId: "org-1",
  missionId: "mission-1",
});

test("mission landing and Ops rail share destinations and administrative admission", async () => {
  const model = fixture();
  const wrapper = mount(WorkspaceLanding, { props: props(model) });
  const rail = (admin: boolean) =>
    opsNavigation({
      mission: { mission_id: "mission-1" },
      capabilities: admin ? ["organization_admin"] : [],
    }).groups.flatMap((group: { items: { href: string }[] }) =>
      group.items.map((item) => item.href),
    );
  expect(wrapper.findAll("nav a").map((link) => link.attributes("href"))).toEqual(rail(false));
  expect(wrapper.find("#ops-entry-activations").exists()).toBe(false);
  expect(wrapper.get("#ops-entry-commands").attributes("data-phx-link")).toBe("redirect");
  expect(wrapper.text()).toContain("Firebird");
  expect(wrapper.text()).not.toContain("components available");
  expect(wrapper.text()).not.toContain("Server authority connected");
  await wrapper.setProps(props({ ...model, can_administer: true }));
  expect(wrapper.findAll("nav a").map((link) => link.attributes("href"))).toEqual(rail(true));
  expect(wrapper.get("#ops-entry-activations").attributes("href")).toBe(
    "/missions/mission-1/ops/activations",
  );
  wrapper.unmount();
});

test.each([
  null,
  {},
  { ...fixture(), version: 2 },
  { ...fixture(), can_administer: "false" },
  { ...fixture(), mission_name: " " },
  { ...fixture(), context: { organization_id: "foreign", mission_id: "mission-1" } },
  { ...fixture(), context: { organization_id: "org-1", mission_id: "foreign" } },
])("malformed or foreign navigation is unavailable without rendering destinations: %j", (model) => {
  const wrapper = mount(WorkspaceLanding, { props: props(model) });
  expect(wrapper.get("#ops-workspace-landing-unavailable").attributes("role")).toBe("alert");
  expect(wrapper.findAll("a")).toHaveLength(0);
  wrapper.unmount();
});

test("scope changes remove old mission links and valid replacement recovers", async () => {
  const wrapper = mount(WorkspaceLanding, { props: props() });
  await wrapper.setProps({ missionId: "mission-2" });
  expect(wrapper.findAll("a")).toHaveLength(0);
  await wrapper.setProps({
    model: { ...fixture(), context: { organization_id: "org-1", mission_id: "mission-2" } },
  });
  expect(wrapper.get("#ops-entry-dashboards").attributes("href")).toBe(
    "/missions/mission-2/ops/dashboards",
  );
  expect(() => readWorkspaceLanding(fixture(), "org-1", "../foreign")).toThrow();
  wrapper.unmount();
});

test("actual producer renders scoped navigation without accepting server supplied destinations", () => {
  const model = process.env.CADENCE_WORKSPACE_LANDING_DOCUMENT
    ? JSON.parse(process.env.CADENCE_WORKSPACE_LANDING_DOCUMENT)
    : fixture();
  const input = {
    ...model,
    href: "https://foreign.test",
    destinations: [{ href: "javascript:alert(1)" }],
  };
  const wrapper = mount(WorkspaceLanding, {
    props: {
      model: input,
      organizationId: model.context.organization_id,
      missionId: model.context.mission_id,
    },
  });
  expect(wrapper.find("#ops-workspace-landing-unavailable").exists()).toBe(false);
  expect(wrapper.get("#ops-entry-dashboards").attributes("href")).toBe(
    `/missions/${encodeURIComponent(model.context.mission_id)}/ops/dashboards`,
  );
  expect(wrapper.find("#ops-entry-activations").exists()).toBe(model.can_administer);
  expect(wrapper.text()).toContain(model.mission_name);
  expect(
    wrapper
      .findAll("a")
      .every((link) =>
        link
          .attributes("href")
          ?.startsWith(`/missions/${encodeURIComponent(model.context.mission_id)}/ops/`),
      ),
  ).toBe(true);
  wrapper.unmount();
});
