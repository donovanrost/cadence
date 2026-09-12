import { required } from "../../../../../test-support/required";
import {
  jsonFixture,
  fixtureRecord,
  fixtureString,
} from "../../../../../test-support/json-fixture";
import { admitFleetStart, windowValid } from "./fleet-start";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { OpsFleetPlanningNew } from "../../fleet-planning";
import {
  startFixture,
  startReviewFixture,
  startReceiptFixture,
  startCompletion,
} from "./fleet-start.test-support";
import type { FleetStartPort } from "./OpsFleetPlanningNew.contracts";

function harness() {
  const model = startFixture();
  const execute = vi.fn<FleetStartPort["execute"]>(async (...[action, input]) => {
    const review = startReviewFixture(
      model,
      input.fleet_run,
      action === "preview" ? input.requirements_page : 1,
      action === "preview" ? input.templates_page : 1,
    );
    return startCompletion(action === "preview" ? { review } : startReceiptFixture(review));
  });
  const refresh = vi.fn(async () => model);
  const wrapper = mount(OpsFleetPlanningNew, {
    props: { start: model, port: { context: model.context, execute, refresh } },
  });
  return { model, execute, refresh, wrapper };
}

test("native review captures UTC fields and create sends the reviewed evidence", async () => {
  const { model, execute, wrapper } = harness();
  await wrapper.get("#fleet-start-horizon-end").setValue("2026-09-09T09:00:00");
  await wrapper.get("#fleet-start-recurring").setValue(true);
  expect(wrapper.find("#fleet-start-create").exists()).toBe(false);
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  const window = {
    ...model.defaults,
    horizon_end: "2026-09-09T09:00:00.000Z",
    include_recurring: true,
  };
  expect(execute).toHaveBeenCalledExactlyOnceWith("preview", {
    fleet_run: window,
    requirements_page: 1,
    templates_page: 1,
  });
  const review = startReviewFixture(model, window);
  expect(wrapper.get("#fleet-start-requirement-requirement-1 a").attributes("href")).toBe(
    "/missions/mission-one/ops/requirements/requirement-1?version=3",
  );
  await wrapper.get("#fleet-start-create").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenLastCalledWith("create", {
    fleet_run: window,
    evidence: review.evidence,
  });
  expect(wrapper.get("#fleet-start-open-run").attributes("href")).toBe(
    "/missions/mission-one/ops/planning/runs/run-one",
  );
  expect(wrapper.get("#fleet-start-create").attributes("disabled")).toBeDefined();
  expect(wrapper.emitted("create-fleet-run")).toBeUndefined();
  wrapper.unmount();
});

test("editing the form invalidates its review and policy horizon bounds prevent review", async () => {
  const { execute, wrapper } = harness();
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  expect(wrapper.find("#fleet-start-review").exists()).toBe(true);
  await wrapper.get("#fleet-start-recurring").setValue(true);
  expect(wrapper.find("#fleet-start-review").exists()).toBe(false);
  await wrapper.get("#fleet-start-horizon-end").setValue("2026-09-12T08:00:00");
  expect(wrapper.get("#fleet-start-preview").attributes("disabled")).toBeDefined();
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});

test("review pages carry the captured horizon and are not automatic effects", async () => {
  const { model, execute, wrapper } = harness();
  execute.mockImplementation(async (...[action, input]) =>
    startCompletion({
      review: startReviewFixture(
        model,
        input.fleet_run,
        action === "preview" ? input.requirements_page : 1,
        action === "preview" ? input.templates_page : 1,
        26,
      ),
    }),
  );
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  await wrapper.get("#fleet-start-requirements-next").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenLastCalledWith("preview", {
    fleet_run: model.defaults,
    requirements_page: 2,
    templates_page: 1,
  });
  expect(wrapper.find("#fleet-start-requirement-requirement-26").exists()).toBe(true);
  expect(wrapper.find("#fleet-start-requirement-requirement-1").exists()).toBe(false);
  expect(execute.mock.calls.every(([action]) => action === "preview")).toBe(true);
  wrapper.unmount();
});

test("foreign, changed-policy, malformed and wrong-page reviews never enable creation", async () => {
  for (const mutate of [
    (r: ReturnType<typeof startReviewFixture>) =>
      (r.context = { ...r.context, mission_id: "foreign" }),
    (r: ReturnType<typeof startReviewFixture>) => (r.policy = { ...r.policy, version: 3 }),
    (r: ReturnType<typeof startReviewFixture>) => (r.requirements.page = 2),
    (r: ReturnType<typeof startReviewFixture>) => (r.evidence.input_sha256 = "invalid"),
    (r: ReturnType<typeof startReviewFixture>) =>
      r.requirements.entries.push(required(r.requirements.entries[0])),
    (r: ReturnType<typeof startReviewFixture>) =>
      (r.window.horizon_end = "2026-09-09T10:00:00.000Z"),
  ]) {
    const { model, execute, wrapper } = harness();
    const review = startReviewFixture(model);
    mutate(review);
    execute.mockResolvedValue(startCompletion({ review }));
    await wrapper.get("#fleet-start-form").trigger("submit");
    await flushPromises();
    expect(wrapper.find("#fleet-start-create").exists()).toBe(false);
    expect(wrapper.get("#fleet-start-notice").text()).toContain("could not be reviewed");
    wrapper.unmount();
  }
});

test("unknown creation stays locked through read recovery and is never retried", async () => {
  const { execute, refresh, wrapper } = harness();
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  execute.mockRejectedValue(new Error("receipt lost"));
  await wrapper.get("#fleet-start-create").trigger("click");
  await flushPromises();
  expect(wrapper.find("#fleet-start-uncertain").exists()).toBe(true);
  await wrapper.get("#fleet-start-refresh").trigger("click");
  await flushPromises();
  expect(refresh).toHaveBeenCalledExactlyOnceWith();
  expect(wrapper.find("#fleet-start-uncertain").exists()).toBe(true);
  expect(wrapper.get("#fleet-start-preview").attributes("disabled")).toBeDefined();
  expect(execute).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});

test("a confirmed receipt survives a failed read and an empty review cannot create", async () => {
  const { execute, refresh, model, wrapper } = harness();
  execute.mockResolvedValue(
    startCompletion({ review: startReviewFixture(model, model.defaults, 1, 1, 0) }),
  );
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#fleet-start-create").attributes("disabled")).toBeDefined();
  expect(wrapper.find("#fleet-start-no-demand").exists()).toBe(true);
  execute.mockResolvedValue(startCompletion({ review: startReviewFixture(model) }));
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  execute.mockResolvedValue(startCompletion(startReceiptFixture(startReviewFixture(model))));
  await wrapper.get("#fleet-start-create").trigger("click");
  await flushPromises();
  refresh.mockRejectedValue(new Error("read unavailable"));
  await wrapper.get("#fleet-start-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.find("#fleet-start-receipt").exists()).toBe(true);
  expect(wrapper.get("#fleet-start-notice").text()).toContain("retained");
  wrapper.unmount();
});

test("unsupported initial data can recover, while a missing approved policy keeps creation closed", async () => {
  const model = startFixture();
  const refresh = vi.fn(async () => model);
  const wrapper = mount(OpsFleetPlanningNew, {
    props: { start: null, port: { context: model.context, refresh, execute: vi.fn() } },
  });
  expect(wrapper.find("#fleet-start-unavailable").exists()).toBe(true);
  await wrapper.get("#fleet-start-retry").trigger("click");
  await flushPromises();
  expect(wrapper.find("#fleet-start-form").exists()).toBe(true);
  await wrapper.setProps({ start: { ...model, policy: null } });
  expect(wrapper.find("#fleet-start-policy-required").exists()).toBe(true);
  expect(wrapper.find("#fleet-start-form").exists()).toBe(false);
  wrapper.unmount();
});

test("replacing props while creation is pending ignores the late receipt and retains uncertainty", async () => {
  const { model, execute, wrapper } = harness();
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  let done!: (value: unknown) => void;
  execute.mockImplementation(
    () =>
      new Promise((resolve) => {
        done = resolve;
      }),
  );
  await wrapper.get("#fleet-start-create").trigger("click");
  await wrapper.setProps({ start: structuredClone(model) });
  done(startCompletion(startReceiptFixture(startReviewFixture(model))));
  await flushPromises();
  expect(wrapper.find("#fleet-start-receipt").exists()).toBe(false);
  expect(wrapper.find("#fleet-start-uncertain").exists()).toBe(true);
  wrapper.unmount();
});

test("producer-supplied fleet creation workflow", async () => {
  if (!process.env.CADENCE_FLEET_START) return;
  const supplied = jsonFixture(process.env.CADENCE_FLEET_START);
  const model = required(admitFleetStart(supplied.model)),
    window = supplied.window;
  if (!windowValid(window)) throw Error("Invalid native fleet window");
  const execute = vi.fn().mockRejectedValue(Error("Captured request"));
  const wrapper = mount(OpsFleetPlanningNew, {
    props: {
      start: model,
      port: {
        context: model.context,
        execute,
        refresh: vi.fn(),
      },
    },
  });
  expect(wrapper.find("#fleet-start-form").exists()).toBe(true);
  await wrapper.get("#fleet-start-horizon-start").setValue(window.horizon_start.slice(0, 19));
  await wrapper.get("#fleet-start-horizon-end").setValue(window.horizon_end.slice(0, 19));
  await wrapper.get("#fleet-start-recurring").setValue(window.include_recurring);
  if (supplied.review) execute.mockResolvedValueOnce(startCompletion({ review: supplied.review }));
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  let action = "preview";
  if (supplied.review) {
    expect(wrapper.find("#fleet-start-review").exists()).toBe(true);
    if (supplied.receipt) execute.mockResolvedValueOnce(startCompletion(supplied.receipt));
    await wrapper.get("#fleet-start-create").trigger("click");
    await flushPromises();
    action = "create";
    if (supplied.receipt)
      expect(wrapper.get("#fleet-start-open-run").attributes("href")).toContain(
        encodeURIComponent(fixtureString(fixtureRecord(supplied.receipt).fleetPlanningRunId)),
      );
  }
  expect(execute.mock.calls.at(-1)?.[0]).toBe(action);
  process.stdout.write(
    `FLEET_START_PAYLOAD=${JSON.stringify(required(execute.mock.calls.at(-1))[1])}\n`,
  );
  wrapper.unmount();
});
