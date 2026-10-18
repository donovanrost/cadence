import { required } from "../../../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { OpsFleetPlanning } from "../../fleet-planning";
import { directoryFixture } from "./fleet-directory.test-support";
import { admitFleetDirectory } from "./fleet-directory";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";

let header = pageHeaderHarness("/missions/:mission_id/ops/planning");
function mountPlanning(props: InstanceType<typeof OpsFleetPlanning>["$props"]) {
  header = pageHeaderHarness("/missions/:mission_id/ops/planning");
  return mount(OpsFleetPlanning, { props, global: { provide: header.provide } });
}

test("real run links and native filters preserve the mission and pinned candidate version", () => {
  const directory = directoryFixture();
  required(directory.runs.entries[0]).candidate_plan = { id: "plan-one", version: 3 };
  const wrapper = mountPlanning({ directory });
  expect(wrapper.get("#fleet-run-run-1 a").attributes("href")).toBe(
    "/missions/mission-one/ops/planning/runs/run-1",
  );
  expect(
    wrapper.find('a[href="/missions/mission-one/ops/plans/plan-one?version=3"]').exists(),
  ).toBe(true);
  expect(wrapper.get("#fleet-directory-filter").attributes()).toMatchObject({
    method: "get",
    action: "/missions/mission-one/ops/planning",
  });
  expect(wrapper.get("#fleet-directory-state").attributes("name")).toBe("state");
  expect(header.href("plan-horizon")).toBe("/missions/mission-one/ops/planning/new");
  expect(header.header().refresh?.pending).toBe(true);
  expect(wrapper.find("#fleet-directory-next").exists()).toBe(false);
  wrapper.unmount();
});

test("paging retains the lifecycle filter, and an empty later page keeps a way back", () => {
  const directory = directoryFixture(25);
  directory.query = { page: 2, state: "queued" };
  directory.runs.page = 2;
  const wrapper = mountPlanning({ directory });
  expect(wrapper.get("#fleet-directory-next").attributes("href")).toBe(
    "/missions/mission-one/ops/planning?page=3&state=queued",
  );
  expect(wrapper.get("#fleet-directory-previous").attributes("href")).toBe(
    "/missions/mission-one/ops/planning?page=1&state=queued",
  );
  wrapper.unmount();
  directory.runs = { page: 2, entries: [], more: false };
  directory.active_policy = null;
  const empty = mountPlanning({ directory });
  expect(empty.find("#fleet-planning-runs-empty").exists()).toBe(true);
  expect(empty.find("#fleet-directory-previous").exists()).toBe(true);
  expect(empty.find("#fleet-planning-policy-required").exists()).toBe(true);
  expect(header.has("plan-horizon")).toBe(false);
  empty.unmount();
});

test("rejects malformed versions, scope, duplicate IDs, bounds, and inconsistent filters", () => {
  const values: unknown[] = [null, {}, { ...directoryFixture(), contract_version: 2 }];
  const mutate = (change: (v: ReturnType<typeof directoryFixture>) => void) => {
    const v = directoryFixture();
    change(v);
    values.push(v);
  };
  mutate((v) => v.runs.entries.push(required(v.runs.entries[0])));
  mutate((v) => (v.runs.more = true));
  mutate((v) => (v.query.state = "failed"));
  mutate((v) => (v.runs.page = 2));
  mutate((v) => (required(v.runs.entries[0]).requirement_count = 10001));
  mutate(
    (v) => (required(v.runs.entries[0]).horizon_end = required(v.runs.entries[0]).horizon_start),
  );
  mutate((v) => (required(v.runs.entries[0]).candidate_plan = { id: "plan-one", version: 0 }));
  mutate((v) => (required(v.active_policy).content_sha256 = "wrong"));
  mutate((v) => (v.context.mission_id = "foreign"));
  for (const directory of values) {
    const wrapper = mountPlanning({
      directory,
      port: { context: directoryFixture().context, refresh: vi.fn() },
    });
    expect(wrapper.find("#fleet-directory-unavailable").exists()).toBe(true);
    expect(wrapper.find("#fleet-run-run-1").exists()).toBe(false);
    wrapper.unmount();
  }
  expect(admitFleetDirectory(directoryFixture())).not.toBeNull();
});

test("refresh is read-only, keeps the captured page, and retains evidence on failed reads", async () => {
  const directory = directoryFixture();
  const refresh = vi.fn().mockResolvedValue(directoryFixture());
  const wrapper = mountPlanning({ directory, port: { context: directory.context, refresh } });
  await header.refresh();
  await flushPromises();
  expect(refresh).toHaveBeenCalledExactlyOnceWith();
  expect(wrapper.get("#fleet-directory-notice").text()).toBe("Fleet directory refreshed.");
  const different = directoryFixture();
  different.query.page = 2;
  different.runs.page = 2;
  refresh.mockResolvedValue(different);
  await header.refresh();
  await flushPromises();
  expect(wrapper.get("#fleet-directory-notice").text()).toContain("retained");
  expect(wrapper.find("#fleet-directory-previous").exists()).toBe(false);
  refresh.mockRejectedValue(new Error("Read denied"));
  await header.refresh();
  await flushPromises();
  expect(wrapper.find("#fleet-run-run-1").exists()).toBe(true);
  expect(wrapper.get("#fleet-directory-notice").text()).toContain("retained");
  expect(wrapper.emitted("refresh-planning")).toBeUndefined();
  wrapper.unmount();
});

test("retry can recover invalid initial evidence and a late response cannot replace new props", async () => {
  let resolve!: (value: unknown) => void;
  const refresh = vi.fn(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const directory = directoryFixture();
  const wrapper = mountPlanning({ directory: null, port: { context: directory.context, refresh } });
  await wrapper.get("#fleet-directory-retry").trigger("click");
  await wrapper.get("#fleet-directory-retry").trigger("click");
  expect(refresh).toHaveBeenCalledTimes(1);
  resolve(directory);
  await flushPromises();
  expect(wrapper.find("#fleet-run-run-1").exists()).toBe(true);
  void header.refresh();
  const next = directoryFixture();
  required(next.runs.entries[0]).id = "new-run";
  await wrapper.setProps({ directory: next });
  resolve(directory);
  await flushPromises();
  expect(wrapper.find("#fleet-run-new-run").exists()).toBe(true);
  expect(wrapper.find("#fleet-run-run-1").exists()).toBe(false);
  wrapper.unmount();
});
