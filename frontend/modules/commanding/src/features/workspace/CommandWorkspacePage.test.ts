import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import CommandWorkspacePage from "./CommandWorkspacePage.vue";
import { workspaceFixture } from "./fixtures.test-support";
import type { WorkspacePage } from "./contracts";

test("live access changes switch between preparation and observation and clean up subscriptions", async () => {
  const initial = workspaceFixture();
  let current: WorkspacePage = initial;
  const listeners = new Set<() => void>();
  const wrapper = mount(CommandWorkspacePage, {
    props: {
      page: initial,
      context: initial.directory.context,
      port: { execute: vi.fn(), navigate: vi.fn(), guardNavigation: () => () => {} },
      refresh: vi.fn(),
      readPort: {
        read: async () => current,
        subscribe(listener: () => void) {
          listeners.add(listener);
          return () => {
            listeners.delete(listener);
          };
        },
      },
    },
  });
  try {
    await flushPromises();
    expect(wrapper.find("#command-workspace").exists()).toBe(true);
    current = { state: "observe", monitor: { ...initial.monitor, can_review: false } };
    for (const notify of listeners) notify();
    await flushPromises();
    expect(wrapper.find("#command-workspace").exists()).toBe(false);
    expect(wrapper.find("#command-monitor").exists()).toBe(true);
    expect(listeners.size).toBe(1);
    current = initial;
    for (const notify of listeners) notify();
    await flushPromises();
    expect(wrapper.find("#command-workspace").exists()).toBe(true);
    expect(wrapper.find("#command-monitor").exists()).toBe(false);
  } finally {
    wrapper.unmount();
  }
  expect(listeners.size).toBe(0);
});
