import { producerFixture } from "../../../../../test-support/producer-fixture";
import {
  jsonFixture,
  fixtureRecord,
  fixtureString,
} from "../../../../../test-support/json-fixture";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { fleetDirectoryContribution } from "../../fleet-planning";
import { planningContributions } from "../../contributions";
import { directoryFixture } from "./fleet-directory.test-support";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
const context = { organizationId: "org-one", missionId: "mission-one" };
test("public contribution owns admission and uses the existing fleet workflow", async () => {
  const directory = directoryFixture();
  expect(planningContributions).toContain(fleetDirectoryContribution);
  const read = vi.fn().mockResolvedValue(directory);
  const header = pageHeaderHarness("/missions/:mission_id/ops/planning");
  const wrapper = mount(fleetDirectoryContribution.component, {
    props: { ...fleetDirectoryContribution.read(directory, context), readPort: { read } },
    global: { provide: header.provide },
  });
  await header.refresh();
  await flushPromises();
  expect(read).toHaveBeenCalledOnce();
  expect(wrapper.find("#fleet-run-run-1").exists()).toBe(true);
  for (const invalid of [
    { ...context, missionId: "foreign" },
    { ...context, resourceId: "run-one" },
  ])
    expect(() => fleetDirectoryContribution.read(directory, invalid)).toThrow();
  expect(() =>
    fleetDirectoryContribution.read({ ...directory, contract_version: 2 }, context),
  ).toThrow();
  wrapper.unmount();
});
const producer = producerFixture("CADENCE_FLEET_CONTRIBUTION", import.meta.url);
test.skipIf(!producer.available)("producer-supplied directory contribution", async () => {
  const snapshot = jsonFixture(producer.read()),
    rawContext = fixtureRecord(snapshot.context);
  const context = {
    organizationId: fixtureString(rawContext.organizationId),
    missionId: fixtureString(rawContext.missionId),
  };
  const read = vi.fn().mockResolvedValue(snapshot.data);
  const header = pageHeaderHarness("/missions/:mission_id/ops/planning");
  const wrapper = mount(fleetDirectoryContribution.component, {
    props: {
      ...fleetDirectoryContribution.read(snapshot.data, context),
      readPort: { read },
    },
    global: { provide: header.provide },
  });
  expect(wrapper.find("#ops-fleet-planning-page").exists()).toBe(true);
  await header.refresh();
  await flushPromises();
  expect(read).toHaveBeenCalledOnce();
  wrapper.unmount();
});
