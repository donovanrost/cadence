import { producerFixture } from "../../../../../test-support/producer-fixture";
import { required } from "../../../../../test-support/required";
import {
  jsonFixture,
  fixtureRecord,
  fixtureString,
} from "../../../../../test-support/json-fixture";
import type { OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import { windowValid } from "./fleet-start";
import { mount, flushPromises } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { expect, test, vi } from "vite-plus/test";
import { fleetStartContribution, fleetRunContribution } from "../../fleet-planning";
import { planningContributions } from "../../contributions";
import {
  startFixture,
  startCompletion,
  startReviewFixture,
  startReceiptFixture,
} from "./fleet-start.test-support";
import { runFixture } from "./fleet-run.test-support";
const context = { organizationId: "org-one", missionId: "mission-one" };

test("public workflow contributions bind context, resources and their declared actions", () => {
  for (const c of [fleetStartContribution, fleetRunContribution])
    expect(planningContributions).toContain(c);
  expect(fleetStartContribution.actions).toEqual(["validate-fleet-run", "create-fleet-run"]);
  expect(fleetRunContribution.actions).toEqual(["refresh-fleet-run", "repair-fleet-run"]);
  expect(fleetStartContribution.read(startFixture(), context)).toHaveProperty("start");
  expect(
    fleetRunContribution.read(runFixture(), { ...context, resourceId: "run-one" }),
  ).toHaveProperty("run");
  for (const invalid of [
    { ...context, missionId: "foreign" },
    { ...context, resourceId: "foreign" },
  ]) {
    expect(() => fleetStartContribution.read(startFixture(), invalid)).toThrow();
    expect(() => fleetRunContribution.read(runFixture(), invalid)).toThrow();
  }
  expect(() => fleetRunContribution.read(runFixture(), context)).toThrow();
  expect(() =>
    fleetStartContribution.read({ ...startFixture(), contract_version: 2 }, context),
  ).toThrow();
});

test("the start adapter preserves reviewed native payloads and successful receipts", async () => {
  const start = startFixture();
  const execute = vi.fn<OpsPagePort["execute"]>(async (action, input) => {
    if (!windowValid(input.fleet_run)) throw Error("Invalid fleet window");
    const review = startReviewFixture(start, input.fleet_run);
    return startCompletion(
      action === "validate-fleet-run" ? { review } : startReceiptFixture(review),
    );
  });
  const read = vi.fn().mockResolvedValue(start);
  const wrapper = mount(
    pageHeaderHarness("/missions/:mission_id/ops/planning/new").stage(
      fleetStartContribution.component,
    ),
    {
      props: {
        ...fleetStartContribution.read(start, context),
        port: { execute, navigate: vi.fn() },
        readPort: { read },
      },
    },
  );
  await wrapper.get("#fleet-start-form").trigger("submit");
  await flushPromises();
  await wrapper.get("#fleet-start-create").trigger("click");
  await flushPromises();
  expect(execute.mock.calls.map(([action]) => action)).toEqual([
    "validate-fleet-run",
    "create-fleet-run",
  ]);
  expect(required(execute.mock.calls[1])[1].evidence).toEqual(startReviewFixture(start).evidence);
  expect(wrapper.get("#fleet-start-open-run").attributes("href")).toBe(
    "/missions/mission-one/ops/planning/runs/run-one",
  );
  await wrapper.get("#page-header-refresh").trigger("click");
  await flushPromises();
  expect(read).toHaveBeenCalledOnce();
  expect(execute).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});

const producer = producerFixture("CADENCE_FLEET_WORKFLOW", import.meta.url);
test.skipIf(!producer.available)("producer-supplied host fleet workflow", async () => {
  const supplied = jsonFixture(producer.read());
  const snapshot = fixtureRecord(supplied.snapshot),
    rawContext = fixtureRecord(snapshot.context);
  const context = {
    organizationId: fixtureString(rawContext.organizationId),
    missionId: fixtureString(rawContext.missionId),
    ...(rawContext.resourceId === undefined
      ? {}
      : { resourceId: fixtureString(rawContext.resourceId) }),
  };
  const contribution =
    snapshot.id === fleetStartContribution.id ? fleetStartContribution : fleetRunContribution;
  const execute = vi.fn<OpsPagePort["execute"]>().mockRejectedValue(Error("Captured request"));
  const route =
    contribution === fleetStartContribution
      ? "/missions/:mission_id/ops/planning/new"
      : "/missions/:mission_id/ops/planning/runs/:fleet_planning_run_id";
  const wrapper = mount(pageHeaderHarness(route).stage(contribution.component), {
    props: {
      ...contribution.read(snapshot.data, context),
      port: { execute, navigate: vi.fn() },
      readPort: { read: vi.fn().mockResolvedValue(snapshot.data) },
    },
  });
  if (contribution === fleetStartContribution) {
    const window = supplied.window;
    if (!windowValid(window)) throw Error("Invalid native fleet window");
    await wrapper
      .get("#fleet-start-horizon-start")
      .setValue(fixtureString(fixtureRecord(supplied.window).horizon_start).slice(0, 19));
    await wrapper
      .get("#fleet-start-horizon-end")
      .setValue(fixtureString(fixtureRecord(supplied.window).horizon_end).slice(0, 19));
    await wrapper.get("#fleet-start-recurring").setValue(window.include_recurring);
    if (supplied.review) execute.mockResolvedValueOnce(supplied.review);
    await wrapper.get("#fleet-start-form").trigger("submit");
    await flushPromises();
    if (supplied.review) {
      if (supplied.receipt) execute.mockResolvedValueOnce(supplied.receipt);
      await wrapper.get("#fleet-start-create").trigger("click");
      await flushPromises();
      if (supplied.receipt) expect(wrapper.find("#fleet-start-open-run").exists()).toBe(true);
    }
  } else if (supplied.action === "repair-fleet-run") {
    await wrapper
      .get("#fleet-run-repair-start")
      .setValue(fixtureString(fixtureRecord(supplied.window).horizon_start).slice(0, 19));
    await wrapper
      .get("#fleet-run-repair-end")
      .setValue(fixtureString(fixtureRecord(supplied.window).horizon_end).slice(0, 19));
    if (supplied.receipt) execute.mockResolvedValueOnce(supplied.receipt);
    await wrapper.get("#fleet-run-repair-form").trigger("submit");
    await flushPromises();
  } else {
    if (supplied.receipt) execute.mockResolvedValueOnce(supplied.receipt);
    await wrapper.get("#fleet-run-continue").trigger("click");
    await flushPromises();
  }
  if (supplied.receipt && contribution === fleetRunContribution)
    expect(wrapper.find("#fleet-run-receipt").exists()).toBe(true);
  expect(execute.mock.calls.at(-1)?.[0]).toBe(supplied.action);
  process.stdout.write(
    `FLEET_CONTRIBUTION_INPUT=${JSON.stringify(required(execute.mock.calls.at(-1))[1])}\n`,
  );
  wrapper.unmount();
});
