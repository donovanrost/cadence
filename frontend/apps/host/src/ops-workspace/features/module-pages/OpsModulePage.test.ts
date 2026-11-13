import "../../../module-pages.test-support";
import type { OpsPageNavigationPort } from "@cadence/plugin-sdk/ops-pages";
import { required } from "../../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import OpsModulePage from "./OpsModulePage.vue";
import { ExplorationPanel } from "@cadence/dashboards-and-exploration/exploration";
import {
  fixture as explorationFixture,
  context as explorationContext,
} from "../../../../../../modules/dashboards-and-exploration/src/features/exploration/fixtures.test-support";
let app: ReturnType<typeof mount>;
afterEach(() => app?.unmount());
test("read-only navigation has no execute capability and expires with its admitted snapshot", async () => {
  const navigation = vi.fn(),
    execute = vi.fn(),
    dispose = vi.fn();
  const guardNavigation = vi.fn(() => dispose);
  const exploration = {
    id: "dashboards.exploration",
    slot: "ops.page",
    version: 1,
    status: "ready",
    context: explorationContext,
    data: explorationFixture(),
  };
  app = mount(OpsModulePage, {
    props: {
      contributionId: exploration.id,
      snapshot: exploration,
      context: explorationContext,
      refresh: vi.fn(),
      navigate: navigation,
      execute,
      guardNavigation,
    },
  });
  const port: OpsPageNavigationPort = app.getComponent(ExplorationPanel).props("port");
  expect(Object.hasOwn(port, "execute")).toBe(false);
  port.navigate("/missions/mission/ops/explore");
  expect(navigation).toHaveBeenCalledOnce();
  exploration.status = "unavailable";
  port.navigate("/missions/mission/ops/explore");
  expect(navigation).toHaveBeenCalledOnce();
  exploration.status = "ready";
  await app.setProps({ refreshing: true });
  port.navigate("/missions/mission/ops/explore");
  expect(navigation).toHaveBeenCalledOnce();
  expect(app.find("#ops-module-unavailable").exists()).toBe(false);
  await app.setProps({
    refreshing: false,
    snapshot: { ...exploration, data: explorationFixture() },
  });
  const replacement: OpsPageNavigationPort = app.getComponent(ExplorationPanel).props("port");
  expect(dispose).toHaveBeenCalledOnce();
  expect(guardNavigation).toHaveBeenCalledTimes(2);
  port.navigate("/missions/mission/ops/explore");
  expect(() => required(port.guardNavigation)(() => false)).toThrow("Inactive");
  expect(navigation).toHaveBeenCalledOnce();
  replacement.navigate("/missions/mission/ops/explore?point_id=other");
  expect(navigation).toHaveBeenCalledTimes(2);
  await app.setProps({ snapshot: { ...exploration, status: "unavailable" } });
  expect(app.find("#ops-module-unavailable").exists()).toBe(true);
  replacement.navigate("/missions/mission/ops/explore");
  expect(navigation).toHaveBeenCalledTimes(2);
  expect(execute).not.toHaveBeenCalled();
  expect(dispose).toHaveBeenCalledTimes(2);
});
