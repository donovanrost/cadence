import "../../../module-pages.test-support";
import type { OpsPageAction } from "@cadence/plugin-sdk/ops-pages";
import { containing } from "../../../../../../test-support/matchers";
import { mount, flushPromises } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import {
  requirementPageFixture,
  requirementOperationFixture,
} from "../../../../../../modules/planning-and-contacts/src/features/contact-requirements/requirement-workflow.test-support";
import OpsModulePage from "./OpsModulePage.vue";
const context = { organizationId: "org-1", missionId: "mission-1", resourceId: "requirement-1" };
let wrapper: ReturnType<typeof mount>;
afterEach(() => {
  wrapper?.unmount();
  window.sessionStorage.clear();
  vi.restoreAllMocks();
});
function harness() {
  const initial = {
    id: "planning.requirement-review",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token: "11111111-1111-4111-8111-111111111111",
    context,
    data: requirementPageFixture(),
  };
  const execute = vi.fn<(request: OpsPageAction) => Promise<unknown>>(),
    query = vi.fn().mockResolvedValue(initial),
    refresh = vi.fn(),
    dispose = vi.fn();
  let guard = () => true;
  const guardNavigation = vi.fn((next: () => boolean) => {
    guard = next;
    return dispose;
  });
  wrapper = mount(OpsModulePage, {
    props: {
      contributionId: initial.id,
      snapshot: initial,
      context,
      execute,
      query,
      refresh,
      navigate: vi.fn(),
      guardNavigation,
    },
  });
  return { initial, execute, query, refresh, dispose, guardNavigation, canLeave: () => guard() };
}
test("host binds planning action and lost receipt recovery to the captured resource and token", async () => {
  const h = harness();
  h.execute.mockImplementationOnce(async ({ event, input }) => {
    if (event !== "plan") throw Error("Unexpected host action");
    const op = requirementOperationFixture(h.initial.data, event, input);
    h.query.mockResolvedValue({
      ...h.initial,
      data: { ...h.initial.data, sequence: op.sequence, operation: op },
    });
    throw Error("Lost receipt");
  });
  await wrapper.get("#plan-contact-requirement").trigger("click");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledExactlyOnceWith(
    containing({
      id: h.initial.id,
      token: h.initial.token,
      event: "plan",
      input: {
        sequence: 1,
        payload: containing({ contact_requirement_id: "requirement-1" }),
      },
    }),
  );
  await wrapper.get("#requirement-review-refresh").trigger("click");
  await flushPromises();
  expect(h.query).toHaveBeenCalledExactlyOnceWith({ id: h.initial.id, token: h.initial.token });
  expect(wrapper.find("#requirement-review-unconfirmed").exists()).toBe(false);
  expect(h.refresh).not.toHaveBeenCalled();
});
test("host navigation honors the feature selection guard when tab storage fails", async () => {
  const storage = window.sessionStorage;
  vi.spyOn(window, "sessionStorage", "get").mockReturnValue({
    getItem: storage.getItem.bind(storage),
    setItem: () => {
      throw Error("Unavailable storage");
    },
    removeItem: storage.removeItem.bind(storage),
    clear: storage.clear.bind(storage),
    key: storage.key.bind(storage),
    get length() {
      return storage.length;
    },
  });
  const h = harness();
  expect(h.guardNavigation).toHaveBeenCalledOnce();
  await wrapper.get("#select-op-1").setValue(true);
  expect(h.canLeave()).toBe(false);
  await wrapper.get("#clear-opportunity-selection").trigger("click");
  expect(h.canLeave()).toBe(true);
  wrapper.unmount();
  expect(h.dispose).toHaveBeenCalledOnce();
});
test("foreign resources and unsupported requirement data stay inside host recovery", async () => {
  const h = harness();
  for (const change of [
    { context: { ...context, resourceId: "foreign" } },
    { data: {} },
    { token: "invalid" },
  ]) {
    await wrapper.setProps({ snapshot: { ...h.initial, ...change } });
    expect(wrapper.find("#ops-module-unavailable").exists()).toBe(true);
  }
  await wrapper.get("#ops-module-retry").trigger("click");
  expect(h.refresh).toHaveBeenCalledOnce();
  expect(h.execute).not.toHaveBeenCalled();
});
