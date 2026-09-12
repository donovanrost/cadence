import { mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import SpacecraftModulePage from "./SpacecraftModulePage.vue";
import {
  context,
  spacecraftCommandingFixture as fixture,
} from "../../../../../../modules/commanding/src/features/spacecraft-commanding/fixtures.test-support";
const snapshot = () => ({
  id: "commanding.spacecraft",
  slot: "spacecraft.page",
  version: 1,
  status: "ready",
  context,
  data: fixture(),
});

test("host composes spacecraft commanding and isolates malformed owner data and contexts", async () => {
  const valid = snapshot();
  const wrapper = mount(SpacecraftModulePage, {
    props: { contributionId: valid.id, context, snapshot: valid, refresh: vi.fn() },
  });
  expect(wrapper.find("#spacecraft-commanding-page").exists()).toBe(true);
  for (const next of [
    { ...valid, context: { ...context, spacecraftId: "foreign" } },
    { ...valid, data: {} },
    { ...valid, status: "unavailable" },
    { ...valid, version: 2 },
  ]) {
    await wrapper.setProps({ snapshot: next });
    expect(wrapper.find("#spacecraft-module-unavailable").exists()).toBe(true);
    expect(wrapper.find("#spacecraft-commanding-page").exists()).toBe(false);
  }
  await wrapper.setProps({ snapshot: snapshot() });
  expect(wrapper.find("#spacecraft-commanding-page").exists()).toBe(true);
  wrapper.unmount();
});
