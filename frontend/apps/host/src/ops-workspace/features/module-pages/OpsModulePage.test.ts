import "../../../module-pages.test-support";
import type { OpsPageNavigationPort } from "@cadence/plugin-sdk/ops-pages";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { required } from "../../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import OpsModulePage from "./OpsModulePage.vue";
import { CommandMonitor } from "@cadence/commanding/mission-commands";
import {
  monitorFixture,
  monitorContext,
} from "../../../../../../modules/commanding/src/features/mission-commands/monitor.test-support";
let app: ReturnType<typeof mount>;
afterEach(() => app?.unmount());
test("read-only navigation has no execute capability and expires with its admitted snapshot", async () => {
  const navigation = vi.fn(),
    execute = vi.fn(),
    dispose = vi.fn();
  const guardNavigation = vi.fn(() => dispose);
  const monitor = {
    id: "commanding.monitor",
    slot: "ops.page",
    version: 1,
    status: "ready",
    context: monitorContext,
    data: monitorFixture(),
  };
  const header = pageHeaderHarness("/missions/:mission_id/ops/commands");
  app = mount(OpsModulePage, {
    props: {
      contributionId: monitor.id,
      snapshot: monitor,
      context: monitorContext,
      refresh: vi.fn(),
      navigate: navigation,
      execute,
      guardNavigation,
    },
    global: { provide: header.provide },
  });
  await flushPromises();
  const port: OpsPageNavigationPort = app.getComponent(CommandMonitor).props("port");
  expect(Object.hasOwn(port, "execute")).toBe(false);
  // An admitted page's guard registers through the host until its snapshot is replaced.
  expect(required(port.guardNavigation)(() => true)).toBe(dispose);
  expect(guardNavigation).toHaveBeenCalledOnce();
  port.navigate("/missions/mission-1/ops/commands");
  expect(navigation).toHaveBeenCalledOnce();
  monitor.status = "unavailable";
  port.navigate("/missions/mission-1/ops/commands");
  expect(navigation).toHaveBeenCalledOnce();
  monitor.status = "ready";
  await app.setProps({ refreshing: true });
  port.navigate("/missions/mission-1/ops/commands");
  expect(navigation).toHaveBeenCalledOnce();
  expect(app.find("#ops-module-unavailable").exists()).toBe(false);
  await app.setProps({
    refreshing: false,
    snapshot: { ...monitor, data: monitorFixture() },
  });
  const replacement: OpsPageNavigationPort = app.getComponent(CommandMonitor).props("port");
  port.navigate("/missions/mission-1/ops/commands");
  expect(() => required(port.guardNavigation)(() => false)).toThrow("Inactive");
  expect(navigation).toHaveBeenCalledOnce();
  replacement.navigate("/missions/mission-1/ops/commands?status=queued");
  expect(navigation).toHaveBeenCalledTimes(2);
  await app.setProps({ snapshot: { ...monitor, status: "unavailable" } });
  expect(app.find("#ops-module-unavailable").exists()).toBe(true);
  replacement.navigate("/missions/mission-1/ops/commands");
  expect(navigation).toHaveBeenCalledTimes(2);
  expect(guardNavigation).toHaveBeenCalledOnce();
  expect(execute).not.toHaveBeenCalled();
});
