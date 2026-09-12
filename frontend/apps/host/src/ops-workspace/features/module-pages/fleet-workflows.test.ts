import type { FleetStartPort } from "../../../../../../modules/planning-and-contacts/src/features/fleet-planning/OpsFleetPlanningNew.contracts";
import type { FleetRunPort } from "../../../../../../modules/planning-and-contacts/src/features/fleet-planning/OpsFleetPlanningRun.contracts";
import { required } from "../../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import {
  OpsFleetPlanningNew,
  OpsFleetPlanningRun,
} from "@cadence/planning-and-contacts/fleet-planning";
import {
  startFixture,
  startReviewFixture,
  startCompletion,
  startReceiptFixture,
} from "../../../../../../modules/planning-and-contacts/src/features/fleet-planning/fleet-start.test-support";
import {
  runFixture,
  repairFixture,
} from "../../../../../../modules/planning-and-contacts/src/features/fleet-planning/fleet-run.test-support";
import OpsModulePage from "./OpsModulePage.vue";
const token = "11111111-1111-4111-8111-111111111111";
let wrapper: ReturnType<typeof mount>;
afterEach(() => wrapper?.unmount());
function harness(
  model: ReturnType<typeof startFixture> | ReturnType<typeof runFixture> = startFixture(),
) {
  const run = "id" in model;
  const context = {
    organizationId: model.context.organization_id,
    missionId: model.context.mission_id,
    ...(run ? { resourceId: model.id } : {}),
  };
  const initial = {
    id: run ? "planning.fleet-run" : "planning.fleet-start",
    slot: "ops.page",
    version: 1,
    status: "ready",
    context,
    token,
    data: model,
  };
  const query = vi.fn().mockResolvedValue(initial),
    execute = vi.fn(),
    refresh = vi.fn();
  wrapper = mount(OpsModulePage, {
    props: {
      contributionId: initial.id,
      snapshot: initial,
      context,
      query,
      execute,
      refresh,
      navigate: vi.fn(),
    },
  });
  return { initial, query, execute, refresh, context };
}
test("host dispatches only declared start actions with captured token and exact review", async () => {
  const h = harness();
  const review = startReviewFixture();
  h.execute
    .mockResolvedValueOnce(startCompletion({ review }))
    .mockResolvedValueOnce(startCompletion(startReceiptFixture(review)));
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  await wrapper.get("#fleet-start-create").trigger("click");
  await flushPromises();
  expect(required(h.execute.mock.calls[0])[0]).toEqual({
    id: h.initial.id,
    token,
    event: "validate-fleet-run",
    input: { fleet_run: review.window, requirements_page: 1, templates_page: 1 },
  });
  expect(required(h.execute.mock.calls[1])[0]).toEqual({
    id: h.initial.id,
    token,
    event: "create-fleet-run",
    input: { fleet_run: review.window, evidence: review.evidence },
  });
  expect(wrapper.find("#fleet-start-open-run").exists()).toBe(true);
  expect(h.query).not.toHaveBeenCalled();
  expect(h.refresh).not.toHaveBeenCalled();
  const port: FleetStartPort = required(wrapper.getComponent(OpsFleetPlanningNew).props("port"));
  // @ts-expect-error The runtime port also rejects actions outside its declared union.
  expect(() => port.execute("repair", {})).toThrow("Undeclared");
});
test("same-context bootstrap copies preserve an in-flight preview and a confirmed creation", async () => {
  const h = harness();
  let settle!: (value: unknown) => void;
  h.execute.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        settle = resolve;
      }),
  );
  await wrapper.get("#fleet-start-form").trigger("submit");
  await wrapper.setProps({ snapshot: structuredClone(h.initial), context: { ...h.context } });
  const review = startReviewFixture();
  settle(startCompletion({ review }));
  await flushPromises();
  expect(wrapper.find("#fleet-start-review").exists()).toBe(true);
  h.execute.mockResolvedValueOnce(startCompletion(startReceiptFixture(review)));
  await wrapper.get("#fleet-start-create").trigger("click");
  await flushPromises();
  await wrapper.setProps({ snapshot: structuredClone(h.initial), context: { ...h.context } });
  expect(wrapper.find("#fleet-start-open-run").exists()).toBe(true);
  expect(wrapper.get("#fleet-start-create").attributes("disabled")).toBeDefined();
});
test("run refresh is read-only and captures the resource, preserving evidence after invalid responses", async () => {
  const model = runFixture(),
    h = harness(model);
  await wrapper.get("#fleet-run-refresh").trigger("click");
  await flushPromises();
  expect(h.query).toHaveBeenCalledExactlyOnceWith({ id: h.initial.id, token });
  expect(h.execute).not.toHaveBeenCalled();
  const bad = [
    { context: { ...h.context, resourceId: "foreign" } },
    { data: { ...model, id: "foreign" } },
    { data: { ...model, query: { ...model.query, requirements_page: 2 } } },
    { data: { ...model, contract_version: 2 } },
  ];
  for (const changed of bad) {
    h.query.mockResolvedValueOnce({ ...h.initial, ...changed });
    await wrapper.get("#fleet-run-refresh").trigger("click");
    await flushPromises();
    expect(wrapper.get("#fleet-run-notice").text()).toContain("Previous evidence is retained");
    expect(wrapper.find("#fleet-run-continue").exists()).toBe(true);
  }
  expect(h.refresh).not.toHaveBeenCalled();
});
test("repair sends the displayed commitment evidence and an unconfirmed receipt remains locked after reads", async () => {
  const model = repairFixture(),
    h = harness(model);
  h.execute.mockRejectedValueOnce(Error("Disconnected"));
  await wrapper.get("#fleet-run-repair-form").trigger("submit");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledExactlyOnceWith({
    id: h.initial.id,
    token,
    event: "repair-fleet-run",
    input: {
      fleet_planning_run_id: model.id,
      evidence: model.repair.evidence,
      repair: { horizon_start: model.horizon_start, horizon_end: model.horizon_end },
    },
  });
  expect(wrapper.find("#fleet-run-uncertain").exists()).toBe(true);
  await wrapper.get("#fleet-run-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.get("#fleet-run-repair-submit").attributes("disabled")).toBeDefined();
  expect(h.execute).toHaveBeenCalledOnce();
});
test("departed run actions reject delayed receipts and cannot execute on the replacement page", async () => {
  const model = runFixture(),
    h = harness(model);
  const port: FleetRunPort = required(wrapper.getComponent(OpsFleetPlanningRun).props("port"));
  let settle!: (value: unknown) => void;
  h.execute.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        settle = resolve;
      }),
  );
  const pending = port.execute("continue", {
    fleet_planning_run_id: model.id,
    evidence: model.evidence,
  });
  const rejected = expect(pending).rejects.toThrow("Inactive");
  await wrapper.setProps({
    snapshot: { ...h.initial, token: "22222222-2222-4222-8222-222222222222" },
  });
  settle(startCompletion({}));
  await rejected;
  await expect(
    port.execute("continue", { fleet_planning_run_id: model.id, evidence: model.evidence }),
  ).rejects.toThrow("Inactive");
  expect(h.execute).toHaveBeenCalledOnce();
});
test("missing resources or capabilities fail inside the host page with retry available", async () => {
  const h = harness(runFixture());
  await wrapper.setProps({ context: { ...h.context, resourceId: "other" } });
  expect(wrapper.find("#ops-module-unavailable").exists()).toBe(true);
  await wrapper.setProps({ context: h.context, query: undefined });
  expect(wrapper.find("#ops-module-unavailable").exists()).toBe(true);
  await wrapper.get("#ops-module-retry").trigger("click");
  expect(h.refresh).toHaveBeenCalledOnce();
});
