import { expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import OpsWorkspaceFrame from "./OpsWorkspaceFrame.vue";
import { readOpsFrameContext } from "./context-contract";
import { context } from "../../../auth-and-navigation/shared/context.test-support";

test("the frame admits producer nulls for absent focus and dashboard selection", () => {
  const value = { ...context, active_dashboard_id: null, fleet_health: null, ops_context: null };
  expect(readOpsFrameContext(value)).toMatchObject({
    active_dashboard_id: null,
    ops_context: null,
  });
  const wrapper = mount(OpsWorkspaceFrame, { props: { context: value } });
  try {
    expect(wrapper.find("#ops-workspace-header").exists()).toBe(true);
  } finally {
    wrapper.unmount();
  }
});

test.each([
  { ...context, mission: null },
  { ...context, dock_surfaces: [{}] },
  { ...context, capabilities: [123] },
  { ...context, ops_context: { modules: [{ key: "unknown" }] } },
  {
    ...context,
    fleet_health: { normalized_state_counts: { red: "3", yellow: 0, blue: 0, green: 1 } },
  },
])("invalid operational context is contained before rendering rails", (value) => {
  expect(readOpsFrameContext(value)).toBeNull();
  const wrapper = mount(OpsWorkspaceFrame, { props: { context: value } });
  try {
    expect(wrapper.get("#ops-context-unavailable").attributes("role")).toBe("alert");
    expect(wrapper.find("#ops-nav-rail").exists()).toBe(false);
  } finally {
    wrapper.unmount();
  }
});
