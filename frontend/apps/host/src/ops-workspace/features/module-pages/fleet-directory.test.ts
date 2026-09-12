import type { FleetDirectoryPort } from "../../../../../../modules/planning-and-contacts/src/features/fleet-planning/OpsFleetPlanning.contracts";
import { required } from "../../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { OpsFleetPlanning } from "@cadence/planning-and-contacts/fleet-planning";
import { directoryFixture } from "../../../../../../modules/planning-and-contacts/src/features/fleet-planning/fleet-directory.test-support";
import OpsModulePage from "./OpsModulePage.vue";
const token = "11111111-1111-4111-8111-111111111111";
const context = { organizationId: "org-one", missionId: "mission-one" };
function snapshot() {
  return {
    id: "planning.fleet-directory",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token,
    context,
    data: directoryFixture(),
  };
}
let wrapper: ReturnType<typeof mount>;
afterEach(() => wrapper?.unmount());
function harness() {
  const initial = snapshot(),
    query = vi.fn().mockResolvedValue(initial),
    refresh = vi.fn(),
    execute = vi.fn();
  wrapper = mount(OpsModulePage, {
    props: { contributionId: initial.id, snapshot: initial, context, query, refresh, execute },
  });
  return { initial, query, refresh, execute };
}
test("captured read port updates evidence without reconnecting or granting effects", async () => {
  const h = harness();
  const next = snapshot();
  required(next.data.runs.entries[0]).id = "updated";
  h.query.mockResolvedValue(next);
  const root = wrapper.get("#ops-fleet-planning-page").element;
  const port: FleetDirectoryPort = required(wrapper.getComponent(OpsFleetPlanning).props("port"));
  expect(Object.hasOwn(port, "execute")).toBe(false);
  await wrapper.get("#refresh-fleet-planning").trigger("click");
  await flushPromises();
  expect(h.query).toHaveBeenCalledExactlyOnceWith({ id: h.initial.id, token });
  expect(wrapper.find("#fleet-run-updated").exists()).toBe(true);
  expect(wrapper.get("#ops-fleet-planning-page").element).toBe(root);
  expect(h.refresh).not.toHaveBeenCalled();
  expect(h.execute).not.toHaveBeenCalled();
});
test("failed and malformed reads retain evidence and admit a later valid recovery", async () => {
  const h = harness();
  const mutations = [
    { slot: "mission.page" },
    { id: "unregistered" },
    { version: 2 },
    { token: "changed" },
    { status: "unavailable" },
    { context: { ...context, missionId: "other" } },
    { data: { ...h.initial.data, contract_version: 2 } },
    {
      data: {
        ...h.initial.data,
        query: { page: 2, state: null },
        runs: { ...h.initial.data.runs, page: 2 },
      },
    },
  ];
  for (const changed of mutations) {
    h.query.mockResolvedValueOnce({ ...h.initial, ...changed });
    await wrapper.get("#refresh-fleet-planning").trigger("click");
    await flushPromises();
    expect(wrapper.find("#fleet-run-run-1").exists()).toBe(true);
    expect(wrapper.find("#ops-module-unavailable").exists()).toBe(false);
  }
  h.query.mockRejectedValueOnce(Error("Disconnected"));
  await wrapper.get("#refresh-fleet-planning").trigger("click");
  await flushPromises();
  expect(wrapper.find("#fleet-run-run-1").exists()).toBe(true);
  await wrapper.get("#refresh-fleet-planning").trigger("click");
  await flushPromises();
  expect(wrapper.get("#fleet-directory-notice").text()).toBe("Fleet directory refreshed.");
});
test("same-context host rerenders cannot rewind a captured read", async () => {
  const h = harness();
  let settle!: (value: unknown) => void;
  h.query.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        settle = resolve;
      }),
  );
  await wrapper.get("#refresh-fleet-planning").trigger("click");
  await wrapper.setProps({ context: { ...context }, snapshot: structuredClone(h.initial) });
  const next = snapshot();
  required(next.data.runs.entries[0]).id = "fresh";
  settle(next);
  await flushPromises();
  expect(wrapper.find("#fleet-run-fresh").exists()).toBe(true);
  await wrapper.setProps({ context: { ...context }, snapshot: structuredClone(h.initial) });
  expect(wrapper.find("#fleet-run-fresh").exists()).toBe(true);
});
test("navigation and replaced tokens expire reads before and after transport", async () => {
  const h = harness();
  const port: FleetDirectoryPort = required(wrapper.getComponent(OpsFleetPlanning).props("port"));
  let settle!: (value: unknown) => void;
  h.query.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        settle = resolve;
      }),
  );
  const pending = port.refresh();
  const rejected = expect(pending).rejects.toThrow("Inactive");
  await wrapper.setProps({
    snapshot: { ...h.initial, token: "22222222-2222-4222-8222-222222222222" },
  });
  settle(h.initial);
  await rejected;
  await expect(port.refresh()).rejects.toThrow("Inactive");
  expect(h.query).toHaveBeenCalledOnce();
});
test("unsupported initial contributions retain the host retry control", async () => {
  const h = harness();
  for (const changed of [{ status: "unavailable" }, { token: "invalid" }, { data: {} }]) {
    await wrapper.setProps({ snapshot: { ...h.initial, ...changed } });
    expect(wrapper.find("#ops-module-unavailable").exists()).toBe(true);
  }
  await wrapper.get("#ops-module-retry").trigger("click");
  expect(h.refresh).toHaveBeenCalledOnce();
  expect(h.query).not.toHaveBeenCalled();
});
import "../../../module-pages.test-support";
