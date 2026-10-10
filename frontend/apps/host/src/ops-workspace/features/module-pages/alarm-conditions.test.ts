import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import "../../../module-pages.test-support";
import { required } from "../../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import OpsModulePage from "./OpsModulePage.vue";
import { alarmFixture } from "../../../../../../modules/limits-and-alarming/src/features/alarm-conditions/testing";
const token = "11111111-1111-4111-8111-111111111111";
let w: ReturnType<typeof mount>;
afterEach(() => w?.unmount());
let header = pageHeaderHarness("/missions/:mission_id/ops/alarms");
function start() {
  const data = alarmFixture(),
    context = { organizationId: data.organization_id, missionId: data.mission_id };
  const snapshot = {
    id: "limits.alarm-conditions",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token,
    context,
    data,
  };
  const query = vi.fn(async () => snapshot),
    execute = vi.fn(),
    refresh = vi.fn(),
    navigate = vi.fn();
  header = pageHeaderHarness("/missions/:mission_id/ops/alarms");
  w = mount(OpsModulePage, {
    props: { contributionId: snapshot.id, snapshot, context, query, execute, refresh, navigate },
    global: { provide: header.provide },
  });
  return { snapshot, query, execute, refresh, navigate };
}
test("host admits the public alarm owner with captured reads and navigation only", async () => {
  const h = start();
  expect(w.find("#ops-alarms-page").exists()).toBe(true);
  await header.refresh();
  await flushPromises();
  expect(h.query).toHaveBeenCalledExactlyOnceWith({ id: h.snapshot.id, token });
  expect(h.execute).not.toHaveBeenCalled();
  expect(h.refresh).not.toHaveBeenCalled();
  // The sub-page link is a host header link; the host shell navigates it.
  expect(header.href("definitions")).toBe(h.snapshot.data.links.definitions);
});
test("same-context bootstrap rerenders cannot rewind a successful refresh", async () => {
  const h = start(),
    next = structuredClone(h.snapshot);
  required(next.data.states.items[0]).value = "47";
  h.query.mockResolvedValueOnce(next);
  await header.refresh();
  await flushPromises();
  expect(w.text()).toContain("Value 47");
  await w.setProps({ snapshot: structuredClone(h.snapshot), context: { ...h.snapshot.context } });
  expect(w.text()).toContain("Value 47");
});
test("wrong tokens or malformed read data retain prior conditions and host navigation", async () => {
  const h = start();
  for (const changed of [
    { token: "wrong" },
    { context: { ...h.snapshot.context, missionId: "foreign" } },
    { data: { ...h.snapshot.data, version: 2 } },
  ]) {
    h.query.mockResolvedValueOnce({ ...h.snapshot, ...changed } as typeof h.snapshot);
    await header.refresh();
    await flushPromises();
    expect(w.find("#ops-module-unavailable").exists()).toBe(false);
    expect(w.findAll("[data-limit-event]")).toHaveLength(1);
    expect(w.get("#alarm-conditions-error").text()).toContain("last loaded evidence");
  }
  await w.setProps({ snapshot: { ...h.snapshot, status: "unavailable" } });
  expect(w.find("#ops-module-unavailable").exists()).toBe(true);
});
