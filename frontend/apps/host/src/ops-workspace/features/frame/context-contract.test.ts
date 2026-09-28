import { expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import OpsWorkspaceFrame from "./OpsWorkspaceFrame.vue";
import { readOpsFrameContext } from "./context-contract";
import { contextSections } from "./context";
import { context } from "../../../auth-and-navigation/shared/context.test-support";

test.each(["Aurora", null])(
  "command context uses the endpoint name rather than its internal key: %s",
  (name) => {
    const value = readOpsFrameContext({
      ...context,
      ops_context: {
        pinned_focus: { kind: "command", id: "request-1" },
        modules: [
          {
            key: "commands",
            status: "info",
            count: 1,
            freshness: "current",
            observed_at: null,
            data: {
              followed_command: {
                command_request_id: "request-1",
                command_name: "NOOP",
                status: "queued",
                target: "spacecraft_runtime:spacecraft-1",
                target_name: name,
              },
            },
          },
        ],
      },
    });
    if (!value) throw Error("Expected command context to be admitted");
    expect(contextSections(value)).toMatchObject([
      { content: { followed_command: { detail: `queued · ${name || "Unnamed target"}` } } },
    ]);
  },
);

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
