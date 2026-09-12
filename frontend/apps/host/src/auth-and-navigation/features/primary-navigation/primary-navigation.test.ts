import { afterEach, expect, test } from "vite-plus/test";
import { mount, type VueWrapper } from "@vue/test-utils";
import PrimaryNavigation from "./PrimaryNavigation.vue";
import { navigation } from "./navigation";
import { context } from "../../shared/context.test-support";
let wrapper: VueWrapper;
afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = "";
});
test("mission sections toggle locally and update their seed when the active route changes", async () => {
  wrapper = mount(PrimaryNavigation, {
    attachTo: document.body,
    props: { mission: true, context: { ...context, nav_item: "mission_overview" } },
  });
  const trigger = wrapper.get('[aria-controls="mission-sidebar-comms-content"]');
  expect(trigger.attributes("aria-expanded")).toBe("false");
  await trigger.trigger("click");
  expect(trigger.attributes("aria-expanded")).toBe("true");
  await wrapper.setProps({ context: { ...context, nav_item: "comms_transports" } });
  expect(
    wrapper.get('a[href="/missions/mission%2F1/comms/transports"]').attributes("aria-current"),
  ).toBe("page");
});
test("capabilities select the compiled primary navigation links", () => {
  expect(navigation(context, false).map((item) => item.key)).toEqual([
    "organization_home",
    "missions",
  ]);
  const admin = { ...context, capabilities: ["organization_admin"] };
  expect(navigation(admin, false).some((item) => item.key === "provider_accounts")).toBe(true);
});
test("an unavailable navigation document retains a safe home destination", async () => {
  wrapper = mount(PrimaryNavigation, { props: { context, mission: true } });
  for (const bad of [
    { ...context, version: 2 },
    { ...context, mission: null },
    { ...context, capabilities: null },
  ]) {
    await wrapper.setProps({ context: bad });
    expect(wrapper.get('a[href="/"]').text()).toBe("Cadence home");
    expect(wrapper.findAll("a")).toHaveLength(1);
  }
  await wrapper.setProps({ context });
  expect(wrapper.find('a[href="/missions/mission%2F1"]').exists()).toBe(true);
});
