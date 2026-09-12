import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { fleetDirectoryContribution } from "../../fleet-planning";
import { planningContributions } from "../../contributions";
import { directoryFixture } from "./fleet-directory.test-support";
const context = { organizationId: "org-one", missionId: "mission-one" };
test("public contribution owns admission and uses the existing fleet workflow", async () => {
  const directory = directoryFixture();
  expect(planningContributions).toContain(fleetDirectoryContribution);
  const read = vi.fn().mockResolvedValue(directory);
  const wrapper = mount(fleetDirectoryContribution.component, {
    props: { ...fleetDirectoryContribution.read(directory, context), readPort: { read } },
  });
  await wrapper.get("#refresh-fleet-planning").trigger("click");
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
test("producer-supplied directory contribution", async () => {
  if (!process.env.CADENCE_FLEET_CONTRIBUTION) return;
  const snapshot = JSON.parse(process.env.CADENCE_FLEET_CONTRIBUTION);
  const read = vi.fn().mockResolvedValue(snapshot.data);
  const wrapper = mount(fleetDirectoryContribution.component, {
    props: {
      ...fleetDirectoryContribution.read(snapshot.data, snapshot.context),
      readPort: { read },
    },
  });
  expect(wrapper.find("#ops-fleet-planning-page").exists()).toBe(true);
  await wrapper.get("#refresh-fleet-planning").trigger("click");
  await flushPromises();
  expect(read).toHaveBeenCalledOnce();
  wrapper.unmount();
});
