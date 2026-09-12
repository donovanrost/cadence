import type { OpsPagePort, OpsPageNavigationPort } from "@cadence/plugin-sdk/ops-pages";
import { required } from "../../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import OpsModulePage from "./OpsModulePage.vue";
import { DashboardEditor } from "@cadence/dashboards-and-exploration/editor";
import {
  editorFixture,
  editorContext,
} from "../../../../../../modules/dashboards-and-exploration/src/features/editor/fixtures.test-support";
import DashboardWorkspace from "../../../../../../modules/dashboards-and-exploration/src/features/workspace/DashboardWorkspace.vue";
import {
  snapshotFixture as workspaceFixture,
  snapshotContext as workspaceContext,
} from "../../../../../../modules/dashboards-and-exploration/src/features/workspace/snapshot-fixture.test-support";
import { directoryFixture } from "../../../../../../modules/dashboards-and-exploration/src/features/directory/fixtures.test-support";
import { ExplorationPanel } from "@cadence/dashboards-and-exploration/exploration";
import {
  fixture as explorationFixture,
  context as explorationContext,
} from "../../../../../../modules/dashboards-and-exploration/src/features/exploration/fixtures.test-support";
const token = "11111111-1111-4111-8111-111111111111";
const context = { organizationId: "org-1", missionId: "mission-1" };
const snapshot = () => ({
  id: "dashboards.directory",
  slot: "ops.page",
  version: 1,
  status: "ready",
  token,
  context,
  data: directoryFixture(),
});
let app: ReturnType<typeof mount>;
afterEach(() => app?.unmount());
test("editor guards span host transitions while commands remain disabled", async () => {
  const state = editorFixture();
  state.dirty = true;
  state.revision = 1;
  const editor = {
    id: "dashboards.editor",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token,
    context: editorContext,
    data: state,
  };
  const execute = vi.fn(),
    remove = vi.fn();
  let guard!: () => boolean;
  vi.stubGlobal(
    "confirm",
    vi.fn(() => false),
  );
  try {
    app = mount(OpsModulePage, {
      props: {
        contributionId: editor.id,
        snapshot: editor,
        context: editorContext,
        refresh: vi.fn(),
        execute,
        navigate: vi.fn(),
        guardNavigation(fn: () => boolean) {
          guard = fn;
          return remove;
        },
      },
    });
    await app.setProps({ refreshing: true, context: { ...editorContext } });
    await flushPromises();
    expect(app.find("#ops-module-unavailable").exists()).toBe(false);
    expect(guard()).toBe(false);
    const port: OpsPagePort = app.getComponent(DashboardEditor).props("port");
    await expect(port.execute("save_draft", {})).rejects.toThrow("Inactive");
    expect(execute).not.toHaveBeenCalled();
    await app.setProps({ refreshing: false, snapshot: { ...editor, status: "unavailable" } });
    expect(app.find("#ops-module-unavailable").exists()).toBe(true);
    expect(guard()).toBe(true);
    expect(() => required(port.guardNavigation)(() => false)).toThrow("Inactive");
    expect(remove).toHaveBeenCalled();
  } finally {
    vi.unstubAllGlobals();
  }
});
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
test("workspace identity is bound at both envelopes and stale viewer ports cannot navigate or execute", async () => {
  const workspace = {
    id: "dashboards.workspace",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token,
    context: workspaceContext,
    data: workspaceFixture(),
  };
  const navigate = vi.fn(),
    execute = vi.fn();
  app = mount(OpsModulePage, {
    props: {
      contributionId: workspace.id,
      snapshot: workspace,
      context: workspaceContext,
      refresh: vi.fn(),
      execute,
      navigate,
    },
  });
  const port: OpsPagePort = app.getComponent(DashboardWorkspace).props("port");
  await expect(port.execute("create", {})).rejects.toThrow();
  expect(execute).not.toHaveBeenCalled();
  await app.setProps({ refreshing: true });
  port.navigate("/missions/mission/ops/dashboards");
  expect(navigate).not.toHaveBeenCalled();
  await app.setProps({ refreshing: false });
  port.navigate("/missions/mission/ops/dashboards");
  expect(navigate).toHaveBeenCalledOnce();
  for (const invalid of [
    { context: { ...workspaceContext, resourceId: "other" } },
    { data: { ...workspaceFixture(), dashboard_id: "other" } },
    { data: { ...workspaceFixture(), document_mode: "draft" } },
    { token: "invalid" },
  ]) {
    await app.setProps({ snapshot: { ...workspace, ...invalid } });
    expect(app.find("#ops-module-unavailable").exists()).toBe(true);
  }
  app.unmount();
  port.navigate("/missions/mission/ops/dashboards");
  expect(navigate).toHaveBeenCalledOnce();
});
test("admits only the compiled Ops registration, matching context, slot, version and token", async () => {
  const refresh = vi.fn(async () => {});
  app = mount(OpsModulePage, {
    props: {
      contributionId: "dashboards.directory",
      snapshot: snapshot(),
      context,
      refresh,
      execute: vi.fn(),
      navigate: vi.fn(),
    },
  });
  expect(app.find("#dashboard-directory-feature").exists()).toBe(true);
  for (const invalid of [
    { slot: "mission.page" },
    { id: "unregistered" },
    { version: 2 },
    { token: "bad" },
    { context: { ...context, missionId: "foreign" } },
    { status: "unavailable" },
  ]) {
    await app.setProps({ snapshot: { ...snapshot(), ...invalid } });
    expect(app.find("#ops-module-unavailable").exists()).toBe(true);
  }
  await app.get("#ops-module-retry").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
});
test("binds action to the admitted page token and contains transport failure", async () => {
  const execute = vi.fn(async () => {
    throw Error("offline");
  });
  app = mount(OpsModulePage, {
    props: {
      contributionId: "dashboards.directory",
      snapshot: snapshot(),
      context,
      refresh: vi.fn(),
      execute,
      navigate: vi.fn(),
    },
  });
  await app.get("#star-dashboard-1").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith({
    id: "dashboards.directory",
    token,
    event: "star",
    input: { dashboard_id: "dashboard-1", expected_version: 3, sequence: 1, starred: false },
  });
  expect(app.get("#star-dashboard-1").attributes("disabled")).toBeDefined();
});
